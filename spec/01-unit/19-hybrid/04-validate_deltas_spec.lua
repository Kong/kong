local helpers = require "spec.helpers"
local txn = require "resty.lmdb.transaction"
local declarative = require "kong.db.declarative"
local validate = require("kong.clustering.services.sync.validate")
local db_errors = require("kong.db.errors")
local declarative_config = require "kong.db.schema.others.declarative_config"


local insert_entity_for_txn = declarative.insert_entity_for_txn
local validate_deltas = validate.validate_deltas
local format_error = validate.format_error


local function lmdb_drop()
  local t = txn.begin(512)
  t:db_drop(false)
  t:commit()
end


local function lmdb_insert(name, entity)
  local t = txn.begin(512)
  local res, err = insert_entity_for_txn(t, name, entity, nil)
  if not res then
    error("lmdb insert failed: " .. err)
  end

  local ok, err = t:commit()
  if not ok then
    error("lmdb t:commit() failed: " .. err)
  end
end


-- insert into LMDB
local function db_insert(bp, name, entity)
  -- insert into dc blueprints
  entity = bp[name]:insert(entity)

  -- insert into LMDB
  lmdb_insert(name, entity)

  assert(kong.db[name]:select({id = entity.id}))

  return entity
end


-- Cache the declarative_config to avoid the overhead of repeatedly executing
-- the time-consuming chain:
--   declarative.new_config -> declarative_config.load -> load_plugin_subschemas
local cached_dc

local function setup_bp()
  -- reset lmdb
  lmdb_drop()

  -- init bp / db ( true for expand_foreigns)
  local bp, db = helpers.get_db_utils("off", nil, nil, nil, nil, true)

  -- init workspaces
  local workspaces = require "kong.workspaces"
  workspaces.upsert_default(db)

  -- init declarative config
  if not cached_dc then
    local err
    cached_dc, err = declarative.new_config(kong.configuration)
    assert(cached_dc, err)
  end

  kong.db.declarative_config = cached_dc

  return bp, db
end


describe("[delta validations]",function()

  local DeclarativeConfig = assert(declarative_config.load(
    helpers.test_conf.loaded_plugins,
    helpers.test_conf.loaded_vaults
  ))

  -- Assert that deltas validation error is same with sync.v1 validation error.
  -- sync.v1 config deltas: @deltas
  -- sync.v2 config table: @config
  local function assert_same_validation_error(deltas, config, expected_errs)
    local _, _, err_t = validate_deltas(deltas)

    assert.equal(err_t.code, 21)
    assert.same(err_t.source, "kong.clustering.services.sync.validate.validate_deltas")
    assert.same(err_t.message, "sync deltas is invalid: {}")
    assert.same(err_t.name, "sync deltas parse failure")

    err_t.code = nil
    err_t.source = nil
    err_t.message = nil
    err_t.name = nil

    local _, dc_err = DeclarativeConfig:validate(config)
    assert(dc_err, "validate config should has error:" .. require("inspect")(config))

    local dc_err_t = db_errors:declarative_config_flattened(dc_err, config)

    dc_err_t.code = nil
    dc_err_t.source = nil
    dc_err_t.message = nil
    dc_err_t.name = nil

    format_error(dc_err_t)

    assert.same(err_t, dc_err_t)

    if expected_errs then
      assert.same(err_t, expected_errs)
    end
  end

  it("workspace id", function()
    local bp = setup_bp()

    -- add entities
    db_insert(bp, "workspaces", { name = "ws-001" })
    local service = db_insert(bp, "services", { name = "service-001", })
    db_insert(bp, "routes", {
      name = "route-001",
      paths = { "/mock" },
      service = { id = service.id },
    })

    local deltas = declarative.export_config_sync()

    for _, delta in ipairs(deltas) do
      local ws_id = delta.ws_id
      assert(ws_id and ws_id ~= ngx.null)

      -- XXX EE: kong-ce entities exported from export_config_sync() do not
      --         contain ws_id field, while kong-ee enntities does.
      -- assert(delta.entity.ws_id)

      -- mannually remove routes ws_id, and then validation will report error
      if delta.type == "routes" then
        delta.entity.ws_id = nil
        delta.ws_id = nil
      end

      if delta.type == "services" then
        delta.entity.ws_id = ngx.null
        delta.ws_id = ngx.null
      end
    end

    local _, _, err_t = validate_deltas(deltas)

    assert.same(err_t, {
      code = 21,
      fields = {
        routes = { "workspace id not found" },
        services = { "workspace id not found" },
      },
      flattened_errors = { },
      message = 'sync deltas is invalid: {routes={"workspace id not found"},services={"workspace id not found"}}',
      name = "sync deltas parse failure",
      source = "kong.clustering.services.sync.validate.validate_deltas",
    })
  end)

  it("route has no required field, but uses default value", function()
    local bp = setup_bp()

    -- add entities
    db_insert(bp, "workspaces", { name = "ws-001" })
    local service = db_insert(bp, "services", { name = "service-001", })
    db_insert(bp, "routes", {
      name = "route-001",
      paths = { "/mock" },
      service = { id = service.id },
    })

    local deltas = declarative.export_config_sync()

    for _, delta in ipairs(deltas) do
      if delta.type == "routes" then
        delta.entity.protocols = nil
        delta.entity.path_handling = nil
        delta.entity.regex_priority = nil
        delta.entity.https_redirect_status_code = nil
        delta.entity.strip_path = nil
        break
      end
    end

    local ok, err = validate_deltas(deltas)
    assert.is_true(ok, "validate should not fail: " .. tostring(err))

    -- after validation the entities in deltas should have default values
    for _, delta in ipairs(deltas) do
      if delta.type == "routes" then
        assert.equal(type(delta.entity.protocols), "table")
        assert.equal(delta.entity.path_handling, "v0")
        assert.equal(delta.entity.regex_priority, 0)
        assert.equal(delta.entity.https_redirect_status_code, 426)
        assert.truthy(delta.entity.strip_path)
        break
      end
    end
  end)

  it("route has unknown field", function()
    local bp = setup_bp()

    -- add entities
    db_insert(bp, "workspaces", { name = "ws-001" })
    local service = db_insert(bp, "services", { name = "service-001", })
    local route = db_insert(bp, "routes", {
      name = "route-001",
      paths = { "/mock" },
      service = { id = service.id },
    })

    local deltas = declarative.export_config_sync()

    for _, delta in ipairs(deltas) do
      if delta.type == "routes" then
        delta.entity.foo = "invalid_field_value"
        break
      end
    end

    local config = declarative.export_config()
    config["routes"][1].foo = "invalid_field_value"

    local errs = {
      fields = {},
      flattened_errors = {{
        entity_id = route.id,
        entity_name = "route-001",
        entity_type = "route",
        errors = {
          {
            field = "foo",
            message = "unknown field",
            type = "field",
          },
        },
      }}
    }

    assert_same_validation_error(deltas, config, errs)
  end)

  it("route has foreign service", function()
    local bp = setup_bp()

    -- add entities
    db_insert(bp, "workspaces", { name = "ws-001" })
    local service = db_insert(bp, "services", { name = "service-001", })
    db_insert(bp, "routes", {
      name = "route-001",
      paths = { "/mock" },
      service = { id = service.id },
    })

    local deltas = declarative.export_config_sync()

    local ok, err = validate_deltas(deltas)
    assert.is_true(ok, "validate should not fail: " .. tostring(err))
  end)

  it("route has unmatched foreign service", function()
    local bp = setup_bp()

    -- add entities
    db_insert(bp, "workspaces", { name = "ws-001" })
    db_insert(bp, "routes", {
      name = "route-001",
      paths = { "/mock" },
      -- unmatched service
      service = { id = "00000000-0000-0000-0000-000000000000" },
    })

    local deltas = declarative.export_config_sync()
    local _, err, err_t = validate_deltas(deltas, false)

    assert.matches(
      "entry 1 of 'services': could not find routes's foreign references services",
      err)

    assert.same(err_t, {
      code = 21,
      fields = {
        routes = {
          services = {
            "could not find routes's foreign references services ({\"id\":\"00000000-0000-0000-0000-000000000000\"})",
          },
        },
      },
      message = [[sync deltas is invalid: {routes={services={"could not find routes's foreign references services ({\"id\":\"00000000-0000-0000-0000-000000000000\"})"}}}]],
      flattened_errors = {},
      name = "sync deltas parse failure",
      source = "kong.clustering.services.sync.validate.validate_deltas",
    })
  end)

  it("100 routes -> 1 services: matched foreign keys", function()
    local bp = setup_bp()

    -- add entities
    db_insert(bp, "workspaces", { name = "ws-001" })
    local service = db_insert(bp, "services", { name = "service-001", })

    for i = 1, 100 do
      db_insert(bp, "routes", {
        name = "route-001",
        paths = { "/mock" },
        -- unmatched service
        service = { id = service.id },
      })
    end

    local deltas = declarative.export_config_sync()
    local ok, err = validate_deltas(deltas, false)
    assert.is_true(ok, "validate should not fail: " .. tostring(err))
  end)

  it("100 routes -> 100 services: matched foreign keys", function()
    local bp = setup_bp()

    -- add entities
    db_insert(bp, "workspaces", { name = "ws-001" })

    for i = 1, 100 do
      local service = db_insert(bp, "services", { name = "service-001", })

      db_insert(bp, "routes", {
        name = "route-001",
        paths = { "/mock" },
        -- unmatched service
        service = { id = service.id },
      })
    end

    local deltas = declarative.export_config_sync()
    local ok, err = validate_deltas(deltas, false)
    assert.is_true(ok, "validate should not fail: " .. tostring(err))
  end)

  it("100 routes: unmatched foreign service", function()
    local bp = setup_bp()

    -- add entities
    db_insert(bp, "workspaces", { name = "ws-001" })

    for i = 1, 100 do
      db_insert(bp, "routes", {
        name = "route-001",
        paths = { "/mock" },
        -- unmatched service
        service = { id = "00000000-0000-0000-0000-000000000000" },
      })
    end

    local deltas = declarative.export_config_sync()
    local _, err = validate_deltas(deltas, false)
    for i = 1, 100 do
      assert.matches(
        "entry " .. i .. " of 'services': " ..
        "could not find routes's foreign references services",
        err)
    end
  end)

  -- The following test cases refer to
  -- spec/01-unit/01-db/01-schema/11-declarative_config/01-validate_spec.lua.

  it("verifies required fields", function()
    local bp = setup_bp()

    -- add entities
    db_insert(bp, "workspaces", { name = "ws-001" })
    local service = db_insert(bp, "services", { name = "service-001", })

    local deltas = declarative.export_config_sync()

    -- delete host field
    for _, delta in ipairs(deltas) do
      if delta.type == "services" then
        delta.entity.host = nil
        break
      end
    end

    local config = declarative.export_config()
    config["services"][1].host = nil

    local errs = {
      fields = {},
      flattened_errors = {{
        entity_id = service.id,
        entity_name = "service-001",
        entity_type = "service",
        errors = {{
          field = "host",
          message = "required field missing",
          type = "field",
        }},
      }},
    }

    assert_same_validation_error(deltas, config, errs)
  end)

  it("performs regular validations", function()
    local bp = setup_bp()

    -- add entities
    db_insert(bp, "workspaces", { name = "ws-001" })
    local _ = db_insert(bp, "services", {
      name = "service-001",
      retries = -1,
      protocol = "foo",
      host = 1234,
      port = 99999,
      path = "/foo//bar/",
    })

    local deltas = declarative.export_config_sync()

    local config = declarative.export_config()

    local errs = {
      fields = {},
      flattened_errors = {
        {
          entity_id = config.services[1].id,
          entity_name = "service-001",
          entity_type = "service",
          errors = {
            {
              field = "retries",
              message = "value should be between 0 and 32767",
              type = "field"
            }, {
              field = "protocol",
              message = "expected one of: grpc, grpcs, http, https, tcp, tls, tls_passthrough, udp",
              type = "field"
            }, {
              field = "port",
              message = "value should be between 0 and 65535",
              type = "field"
            }, {
              field = "path",
              message = "must not have empty segments",
              type = "field"
            }, {
              field = "host",
              message = "expected a string",
              type = "field"
            },
          },
        },
      },
    }

    assert_same_validation_error(deltas, config, errs)
  end)

  it("unloaded plugin", function()
    local bp = setup_bp()

    -- add entities
    db_insert(bp, "workspaces", { name = "ws-001" })

    -- add the unloaded plugin which will trigger a validation error
    db_insert(bp, "plugins", { name = "unloaded-plugin", })

    local deltas = declarative.export_config_sync()

    local config = declarative.export_config()

    local errs = {
      fields = {},
      flattened_errors = {{
        entity_id = config.plugins[1].id,
        entity_name = "unloaded-plugin",
        entity_type = "plugin",
        errors = {{
          field = "name",
          message = "plugin 'unloaded-plugin' not enabled; add it to the 'plugins' configuration property",
          type = "field",
        }},
      }},
    }

    assert_same_validation_error(deltas, config, errs)
  end)

  -- TODO: add more test cases
end)
