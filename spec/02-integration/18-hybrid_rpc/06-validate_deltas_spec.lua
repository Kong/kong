local helpers = require "spec.helpers"
local txn = require "resty.lmdb.transaction"
local declarative = require "kong.db.declarative"


local insert_entity_for_txn = declarative.insert_entity_for_txn
local validate_deltas = require("kong.clustering.services.sync.validate").validate_deltas


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
    end
  end)

  it("route has unknown field", function()
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
        delta.entity.foo = "invalid_field_value"
        break
      end
    end

    local _, err = validate_deltas(deltas)
    assert.matches([[- in entry 1 of 'deltas':
  in 'routes':
    in 'foo': unknown field]],
      err)
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
    local _, err = validate_deltas(deltas, false)
    assert.matches(
      "entry 1 of 'services': could not find routes's foreign refrences services",
      err)
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
        "could not find routes's foreign refrences services",
        err)
    end
  end)
end)
