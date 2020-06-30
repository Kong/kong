local openssl_x509  = require "resty.openssl.x509"
local str           = require "resty.string"
local fixtures_ssl  = require "spec.fixtures.ssl"

local helpers = require "spec.helpers"
local fmt = string.format
local utils = require "kong.tools.utils"


local fixtures_cert = fixtures_ssl.cert
local expected_digest = str.to_hex(openssl_x509.new(fixtures_cert):digest("sha256"))

local uuid = utils.uuid

local PG_HAS_COLUMN_SQL = [[
  SELECT *
  FROM information_schema.columns
  WHERE table_schema = 'public'
  AND table_name     = '%s'
  AND column_name    = '%s';
]]

local PG_HAS_CONSTRAINT_SQL = [[
  SELECT *
  FROM pg_catalog.pg_constraint
  WHERE conname = '%s';
]]

local PG_HAS_INDEX_SQL = [[
  SELECT *
  FROM pg_indexes
  WHERE indexname = '%s';
]]

local PG_HAS_TABLE_SQL = [[
  SELECT *
  FROM pg_catalog.pg_tables
  WHERE schemaname = 'public'
  AND tablename = '%s';
]]

local function assert_pg_has_column(cn, table_name, column_name, data_type)
  local res = assert(cn:query(fmt(PG_HAS_COLUMN_SQL, table_name, column_name)))

  assert.equals(1, #res)
  assert.equals(column_name, res[1].column_name)
  assert.equals(string.lower(data_type), string.lower(res[1].data_type))
end


local function assert_not_pg_has_column(cn, table_name, column_name, data_type)
  local res = assert(cn:query(fmt(PG_HAS_COLUMN_SQL, table_name, column_name)))
  assert.same({}, res)
end


local function assert_pg_has_constraint(cn, constraint_name)
  local res = assert(cn:query(fmt(PG_HAS_CONSTRAINT_SQL, constraint_name)))

  assert.equals(1, #res)
  assert.equals(constraint_name, res[1].conname)
end


local function assert_not_pg_has_constraint(cn, constraint_name)
  local res = assert(cn:query(fmt(PG_HAS_CONSTRAINT_SQL, constraint_name)))
  assert.same({}, res)
end


local function assert_pg_has_index(cn, index_name)
  local res = assert(cn:query(fmt(PG_HAS_INDEX_SQL, index_name)))

  assert.equals(1, #res)
  assert.equals(index_name, res[1].indexname)
end


local function assert_not_pg_has_index(cn, index_name)
  local res = assert(cn:query(fmt(PG_HAS_INDEX_SQL, index_name)))
  assert.same({}, res)
end


local function assert_pg_has_fkey(cn, table_name, column_name)
  assert_pg_has_column(cn, table_name, column_name, "uuid")
  assert_pg_has_constraint(cn, table_name .. "_" .. column_name .. "_fkey")
end


local function assert_not_pg_has_fkey(cn, table_name, column_name)
  assert_not_pg_has_column(cn, table_name, column_name, "uuid")
  assert_not_pg_has_constraint(cn, table_name .. "_" .. column_name .. "_fkey")
end


local function assert_pg_has_table(cn, table_name)
  local res = assert(cn:query(fmt(PG_HAS_TABLE_SQL, table_name)))

  assert.equals(1, #res)
  assert.equals(table_name, res[1].tablename)
end


local function assert_not_pg_has_table(cn, table_name)
  local res = assert(cn:query(fmt(PG_HAS_TABLE_SQL, table_name)))
  assert.same({}, res)
end


local function pg_insert(cn, table_name, tbl)
  local columns, values = {},{}
  for k,_ in pairs(tbl) do
    columns[#columns + 1] = k
  end
  table.sort(columns)
  for i, c in ipairs(columns) do
    local v = tbl[c]
    v = type(v) == "string" and "'" .. v .. "'" or v
    values[i] = tostring(v)
  end
  local sql = fmt([[
    INSERT INTO %s (%s) VALUES (%s)
  ]],
    table_name,
    table.concat(columns, ","),
    table.concat(values, ",")
  )

  local res = assert(cn:query(sql))

  assert.same({ affected_rows = 1 }, res)

  return assert(cn:query(fmt("SELECT * FROM %s WHERE id='%s'", table_name, tbl.id)))[1]
end


describe("#db migration core/009_200_to_210 spec", function()
  local _, db

  after_each(function()
    -- Clean up the database schema after each exercise.
    -- This prevents failed migration tests impacting other tests in the CI
    assert(db:schema_reset())
  end)

  describe("#postgres", function()
    before_each(function()
      _, db = helpers.get_db_utils("postgres", nil, nil, {
        stop_namespace = "kong.db.migrations.core",
        stop_migration = "009_200_to_210",
      })
    end)

    it("adds/removes columns and constraints", function()
      local cn = db.connector
      assert_pg_has_constraint(cn, "ca_certificates_cert_key")
      assert_not_pg_has_column(cn, "ca_certificates", "cert_digest", "text")
      assert_not_pg_has_column(cn, "services", "tls_verify", "boolean")
      assert_not_pg_has_column(cn, "services", "tls_verify_depth", "smallint")
      assert_not_pg_has_column(cn, "services", "ca_certificates", "array")
      assert_not_pg_has_fkey(cn, "upstreams", "client_certificate_id")
      assert_not_pg_has_index(cn, "upstreams_fkey_client_certificate")

      -- kong migrations up
      assert(helpers.run_up_migration(db, "core", "kong.db.migrations.core", "009_200_to_210"))

      -- MIGRATING/AFTER
      assert_not_pg_has_constraint(cn, "ca_certificates_cert_key")
      assert_pg_has_column(cn, "ca_certificates", "cert_digest", "text")
      assert_pg_has_column(cn, "services", "tls_verify", "boolean")
      assert_pg_has_column(cn, "services", "ca_certificates", "array")
      assert_pg_has_fkey(cn, "upstreams", "client_certificate_id")
      assert_pg_has_index(cn, "upstreams_fkey_client_certificate")
    end)

    it("initializes ca_certificates.cert_digest", function()
      local cn = db.connector

      pg_insert(cn, "ca_certificates", { id = uuid(), cert = fixtures_cert })

      -- kong migrations up
      assert(helpers.run_up_migration(db, "core", "kong.db.migrations.core", "009_200_to_210"))

      -- MIGRATING

      -- expect ca_certificates.cert_digest to be empty
      local cc = assert(cn:query("SELECT * FROM ca_certificates;"))[1]
      assert.equals(ngx.null, cc.cert_digest)

      -- kong migrations finish
      assert(helpers.run_teardown_migration(db, "core", "kong.db.migrations.core", "009_200_to_210"))

      -- AFTER
      local cc = assert(cn:query("SELECT * FROM ca_certificates;"))[1]
      assert.equals(expected_digest, cc.cert_digest)
    end)

    it("adds workspaces table, index and ws_id", function()
      local cn = db.connector
      assert_not_pg_has_table(cn, "workspaces")
      assert_not_pg_has_index(cn, "workspaces_name_idx")
      assert_not_pg_has_fkey(cn, "upstreams", "ws_id")
      assert_not_pg_has_fkey(cn, "targets", "ws_id")
      assert_not_pg_has_fkey(cn, "consumers", "ws_id")
      assert_not_pg_has_fkey(cn, "certificates", "ws_id")
      assert_not_pg_has_fkey(cn, "snis", "ws_id")
      assert_not_pg_has_fkey(cn, "services", "ws_id")
      assert_not_pg_has_fkey(cn, "routes", "ws_id")
      assert_not_pg_has_fkey(cn, "plugins", "ws_id")

      -- kong migrations up
      assert(helpers.run_up_migration(db, "core", "kong.db.migrations.core", "009_200_to_210"))

      -- MIGRATING
      assert_pg_has_table(cn, "workspaces")
      assert_pg_has_index(cn, "workspaces_name_idx")
      assert_pg_has_fkey(cn, "upstreams", "ws_id")
      assert_pg_has_fkey(cn, "targets", "ws_id")
      assert_pg_has_fkey(cn, "consumers", "ws_id")
      assert_pg_has_fkey(cn, "certificates", "ws_id")
      assert_pg_has_fkey(cn, "snis", "ws_id")
      assert_pg_has_fkey(cn, "services", "ws_id")
      assert_pg_has_fkey(cn, "routes", "ws_id")
      assert_pg_has_fkey(cn, "plugins", "ws_id")
    end)

    it("correctly handles ws_id", function()
      local cn = db.connector
      -- BEFORE
      -- old node, there isn't even a ws_id column here
      local u = pg_insert(cn, "upstreams", { id = uuid(), name = 'before-upstream', slots = 1 })
      pg_insert(cn, "targets",   { id = uuid(), upstream_id = u.id, target = 'before-target', weight = 1 })
      pg_insert(cn, "consumers", { id = uuid(), username = "before-consumer" })
      local cc = pg_insert(cn, "certificates", { id = uuid(), cert = "before-cert", key = "key" })
      pg_insert(cn, "snis", { id = uuid(), certificate_id = cc.id, name = "before-sni" })
      local s = pg_insert(cn, "services", { id = uuid(), name = "before-service" })
      pg_insert(cn, "routes", { id = uuid(), service_id = s.id })
      pg_insert(cn, "plugins", { id = uuid(), name="key-auth", service_id = s.id, config="{}", enabled = true })

      -- kong migrations up
      assert(helpers.run_up_migration(db, "core", "kong.db.migrations.core", "009_200_to_210"))

      -- MIGRATING
      -- check default workspace exists and get its id
      local res = assert(cn:query("SELECT * FROM workspaces"))
      assert.equals(1, #res)
      assert.equals("default", res[1].name)
      assert.truthy(utils.is_valid_uuid(res[1].id))
      local default_ws_id = res[1].id

      -- ensure that the entities created by the old node get the default ws_id
      local u = assert(cn:query("SELECT * FROM upstreams"))[1]
      local t = assert(cn:query("SELECT * FROM targets"))[1]
      local c = assert(cn:query("SELECT * FROM consumers"))[1]
      local cc = assert(cn:query("SELECT * FROM certificates"))[1]
      local sni = assert(cn:query("SELECT * FROM snis"))[1]
      local s = assert(cn:query("SELECT * FROM services"))[1]
      local r = assert(cn:query("SELECT * FROM routes"))[1]
      local p = assert(cn:query("SELECT * FROM plugins"))[1]
      assert.equals(default_ws_id, u.ws_id)
      assert.equals(default_ws_id, t.ws_id)
      assert.equals(default_ws_id, c.ws_id)
      assert.equals(default_ws_id, cc.ws_id)
      assert.equals(default_ws_id, sni.ws_id)
      assert.equals(default_ws_id, s.ws_id)
      assert.equals(default_ws_id, r.ws_id)
      assert.equals(default_ws_id, p.ws_id)

      -- create entities without specifying default ws_id.
      -- it simulates an "old" kong node inserting entities
      -- expect them to have a workspace id
      local u = pg_insert(cn, "upstreams", { id = uuid(), name = 'old-migrating-upstream', slots = 1 })
      local t = pg_insert(cn, "targets",   { id = uuid(), upstream_id = u.id, target = 'old-migrating-target', weight = 1 })
      local c = pg_insert(cn, "consumers", { id = uuid(), username = "old-migrating-consumer" })
      local cc = pg_insert(cn, "certificates", { id = uuid(), cert = "old-migrating-cert", key = "key" })
      local sni = pg_insert(cn, "snis", { id = uuid(), certificate_id = cc.id, name = "old-migrating-sni" })
      local s = pg_insert(cn, "services", { id = uuid(), name = "old-migrating-service" })
      local r = pg_insert(cn, "routes", { id = uuid(), service_id = s.id })
      local p = pg_insert(cn, "plugins", { id = uuid(), name="key-auth", service_id = s.id, config="{}", enabled = true })
      assert.equals(default_ws_id, u.ws_id)
      assert.equals(default_ws_id, t.ws_id)
      assert.equals(default_ws_id, c.ws_id)
      assert.equals(default_ws_id, cc.ws_id)
      assert.equals(default_ws_id, sni.ws_id)
      assert.equals(default_ws_id, s.ws_id)
      assert.equals(default_ws_id, r.ws_id)
      assert.equals(default_ws_id, p.ws_id)

      -- create those entities specifying ws_id. Simulates a new kong node inserting entities
      -- expect them to have ws_id as well
      local u = pg_insert(cn, "upstreams", { id = uuid(), name = 'new-migrating-upstream', slots = 1, ws_id = default_ws_id })
      local t = pg_insert(cn, "targets",   { id = uuid(), upstream_id = u.id, target = 'new-migrating-target', weight = 1, ws_id = default_ws_id })
      local c = pg_insert(cn, "consumers", { id = uuid(), username = "new-migrating-consumer", ws_id = default_ws_id})
      local cc = pg_insert(cn, "certificates", { id = uuid(), cert = "new-migrating-cert", key = "key", ws_id = default_ws_id })
      local sni = pg_insert(cn, "snis", { id = uuid(), certificate_id = cc.id, name = "new-migrating-sni", ws_id = default_ws_id })
      local s = pg_insert(cn, "services", { id = uuid(), name = "new-migrating-service", ws_id = default_ws_id })
      local r = pg_insert(cn, "routes", { id = uuid(), service_id = s.id, ws_id = default_ws_id })
      local p = pg_insert(cn, "plugins", { id = uuid(), name="key-auth", service_id = s.id, config="{}", enabled = true, ws_id = default_ws_id })
      assert.equals(default_ws_id, u.ws_id)
      assert.equals(default_ws_id, t.ws_id)
      assert.equals(default_ws_id, c.ws_id)
      assert.equals(default_ws_id, cc.ws_id)
      assert.equals(default_ws_id, sni.ws_id)
      assert.equals(default_ws_id, s.ws_id)
      assert.equals(default_ws_id, r.ws_id)
      assert.equals(default_ws_id, p.ws_id)

      -- kong migrations finish
      assert(helpers.run_teardown_migration(db, "core", "kong.db.migrations.core", "009_200_to_210"))

      -- AFTER

      -- create entities without specifying default ws_id.
      -- at this point this should never happen any more (only "new nodes" create entities from now on, and they always should specify ws_id)
      -- but this is a convenient way to test that the default has changed to ngx.null
      local u = pg_insert(cn, "upstreams", { id = uuid(), name = 'old-after-upstream', slots = 1 })
      local t = pg_insert(cn, "targets",   { id = uuid(), upstream_id = u.id, target = 'old-after-target', weight = 1 })
      local c = pg_insert(cn, "consumers", { id = uuid(), username = "old-after-consumer" })
      local cc = pg_insert(cn, "certificates", { id = uuid(), cert = "old-after-cert", key = "key" })
      local sni = pg_insert(cn, "snis", { id = uuid(), certificate_id = cc.id, name = "old-after-sni" })
      local s = pg_insert(cn, "services", { id = uuid(), name = "old-after-service" })
      local r = pg_insert(cn, "routes", { id = uuid(), service_id = s.id })
      local p = pg_insert(cn, "plugins", { id = uuid(), name="key-auth", service_id = s.id, config="{}", enabled = true })
      assert.equals(ngx.null, u.ws_id)
      assert.equals(ngx.null, t.ws_id)
      assert.equals(ngx.null, c.ws_id)
      assert.equals(ngx.null, cc.ws_id)
      assert.equals(ngx.null, sni.ws_id)
      assert.equals(ngx.null, s.ws_id)
      assert.equals(ngx.null, r.ws_id)
      assert.equals(ngx.null, p.ws_id)

      -- create those entities specifying ws_id, simulating a new kong node inserting entities
      -- expect them to have ws_id as well
      local u = pg_insert(cn, "upstreams", { id = uuid(), name = 'new-after-upstream', slots = 1, ws_id = default_ws_id })
      local t = pg_insert(cn, "targets",   { id = uuid(), upstream_id = u.id, target = 'new-after-target', weight = 1, ws_id = default_ws_id })
      local c = pg_insert(cn, "consumers", { id = uuid(), username = "new-after-consumer", ws_id = default_ws_id})
      local cc = pg_insert(cn, "certificates", { id = uuid(), cert = "new-after-cert", key = "key", ws_id = default_ws_id })
      local sni = pg_insert(cn, "snis", { id = uuid(), certificate_id = cc.id, name = "new-after-sni", ws_id = default_ws_id })
      local s = pg_insert(cn, "services", { id = uuid(), name = "new-after-service", ws_id = default_ws_id })
      local r = pg_insert(cn, "routes", { id = uuid(), service_id = s.id, ws_id = default_ws_id })
      local p = pg_insert(cn, "plugins", { id = uuid(), name="key-auth", service_id = s.id, config="{}", enabled = true, ws_id = default_ws_id })
      assert.equals(default_ws_id, u.ws_id)
      assert.equals(default_ws_id, t.ws_id)
      assert.equals(default_ws_id, c.ws_id)
      assert.equals(default_ws_id, cc.ws_id)
      assert.equals(default_ws_id, sni.ws_id)
      assert.equals(default_ws_id, s.ws_id)
      assert.equals(default_ws_id, r.ws_id)
      assert.equals(default_ws_id, p.ws_id)
    end)

    it("correctly migrates plugins composite keys", function()
      -- Assumption on this test: old nodes plugin cache keys will always end in ":"
      -- This has been checked by visually inspecting the call to cache_key, which uses 4 params at most:
      --   https://github.com/Kong/kong/blob/2.0.2/kong/runloop/plugins_iterator.lua#L92-L95
      -- And the implementation of cache_key which concatenates 5 parameters:
      --   https://github.com/Kong/kong/blob/2.0.2/kong/db/dao/init.lua#L1175
      local cn = db.connector
      local s = pg_insert(cn, "services", { id = uuid(), name = "before-srv" })
      local p1 = pg_insert(cn, "plugins", { id = uuid(), name="key-auth", service_id = s.id, config="{}", enabled = true, cache_key="before-cache-key:"})
      assert.same("before-cache-key:", p1.cache_key)

      -- kong migrations up
      assert(helpers.run_up_migration(db, "core", "kong.db.migrations.core", "009_200_to_210"))

      -- MIGRATING
      -- get default ws_id (tested further above)
      local res = assert(cn:query("SELECT * FROM workspaces"))
      local default_ws_id = assert(res[1].id)

      -- simulate an old node creating a service and plugin
      local s = pg_insert(cn, "services", { id = uuid(), name = "old-migrating-srv" })
      local p2 = pg_insert(cn, "plugins", { id = uuid(), name="key-auth", service_id = s.id, config="{}", enabled = true, cache_key="old-migrating-cache-key:"})
      assert.same("old-migrating-cache-key:", p2.cache_key)

      -- simulate a new node creating a service and plugin.
      -- The plugin cache key is expected to already include ws_id
      -- and it is expected to not end in ":"
      local s = pg_insert(cn, "services", { id = uuid(), name = "new-migrating-srv" })
      local p3 = pg_insert(cn, "plugins", { id = uuid(), name="key-auth", service_id = s.id, config="{}", enabled = true, cache_key="new-migrating-cache-key:" .. default_ws_id})
      assert.same("new-migrating-cache-key:" .. default_ws_id, p3.cache_key)

      -- kong migrations teardown
      assert(helpers.run_teardown_migration(db, "core", "kong.db.migrations.core", "009_200_to_210"))

      -- AFTER

      -- the before plugin cache has been updated with ws_id
      local res = assert(cn:query(fmt("SELECT * FROM plugins WHERE cache_key = 'before-cache-key::%s';", default_ws_id)))

      assert.same(p1.id, res[1].id)

      -- the old-migrating cache has been updated with ws_id
      local res = assert(cn:query(fmt("SELECT * FROM plugins WHERE cache_key = 'old-migrating-cache-key::%s';", default_ws_id)))
      assert.same(p2.id, res[1].id)

      -- the new-migrating cache remains the same (ws_id was not added twice)
      local res = assert(cn:query(fmt("SELECT * FROM plugins WHERE cache_key = 'new-migrating-cache-key:%s';", default_ws_id)))
      assert.same(p3.id, res[1].id)
    end)
  end)

--[[
  it("#cassandra", function()
    local uuid = "c37d661d-7e61-49ea-96a5-68c34e83db3a"

    _, db = helpers.get_db_utils("cassandra", nil, nil, {
      stop_namespace = "kong.db.migrations.core",
      stop_migration = "007_140_to_150"
    })

    local cn = db.connector

    -- BEFORE
    assert(cn:query(fmt([[
      INSERT INTO
      routes (partition, id, name, paths)
      VALUES('routes', %s, 'test', ['/']);
    , uuid)))

    local res = assert(cn:query(fmt([[
      SELECT * FROM routes WHERE partition = 'routes' AND id = %s;
    , uuid)))
    assert.same(1, #res)
    assert.same(uuid, res[1].id)
    assert.is_nil(res[1].path_handling)

    -- kong migrations up
    assert(helpers.run_up_migration(db, "core", "kong.db.migrations.core", "007_140_to_150"))

    -- MIGRATING
    res = assert(cn:query(fmt([[
      SELECT * FROM routes WHERE partition = 'routes' AND id = %s;
    , uuid)))
    assert.same(1, #res)
    assert.same(uuid, res[1].id)
    assert.is_nil(res[1].path_handling)

    -- kong migrations finish
    assert(helpers.run_teardown_migration(db, "core", "kong.db.migrations.core", "007_140_to_150"))

    -- AFTER
    res = assert(cn:query(fmt([[
      SELECT * FROM routes WHERE partition = 'routes' AND id = %s;
    , uuid)))
    assert.same(1, #res)
    assert.same(uuid, res[1].id)
    assert.same("v1", res[1].path_handling)
  end)
  ]]
end)
