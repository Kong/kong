local perf = require "spec.helpers.perf"
local split = require "ngx.re".split
local utils = require "spec.helpers.perf.utils"
local workspaces = require "kong.workspaces"
local stringx = require "pl.stringx"
local tablex = require "pl.tablex"

local fmt = string.format

if os.getenv("PERF_TEST_DRIVER") ~= "terraform" then
  error("only runs on terraform driver")
end

-- bump up default instance size
perf.setenv("PERF_TEST_METAL_PLAN", "n2.xlarge.x86") -- 384G ram
perf.setenv("PERF_TEST_EC2_INSTANCE_TYPE", "c5.24xlarge") -- 192G ram
perf.setenv("PERF_TEST_DIGITALOCEAN_SIZE", "m-24vcpu-192gb") -- 192G ram

perf.setenv("PERF_TEST_SEPERATE_DB_NODE", "1")

perf.use_defaults()


local KONG_MODES = {
  'traditional',
  -- 'hybrid',
}

local versions = {}

local env_versions = os.getenv("PERF_TEST_VERSIONS")
if env_versions then
  versions = split(env_versions, ",")
end

local REPEAT_PER_TEST = 0
local WRK_THREADS = 5
local LOAD_DURATION = 60
local NUM_PER_ENTITY = 100 * 1000 -- 100k
local CORE_ENTITIES = {
  "services",
  "routes",
  "consumers",
  "upstreams",
  "targets",
  "plugins",
}

-- Generate entities being used in the test
-- every entity creation will cost ~80μs
local gen_entities = function(db, entities)
  local ws_id = workspaces.get_workspace().id

  local res
  local time = ngx.now()
  local calc_duration = function()
    ngx.update_time()
    local now = ngx.now()
    local duration = now - time
    time = now
    return duration
  end

  -- 01 Services
  res = assert(db.connector:query(fmt([[
    insert into services (id, name, host, retries, port, connect_timeout, write_timeout, read_timeout, protocol, enabled, ws_id)
    select
      gen_random_uuid() AS id,
      i::text AS name,
      CONCAT(i::text, '.local') AS host,
      5 AS retries,
      80 AS port,
      60000 AS connect_timeout,
      60000 AS write_timeout,
      60000 AS read_timeout,
      'http' AS protocol,
      true AS enabled,
      '%s' AS ws_id
    from generate_series(1, %d) s(i)
  ]], ws_id, NUM_PER_ENTITY)))
  print(fmt("Inserted %s services in %d seconds", res.affected_rows, calc_duration()))

  -- 02 Routes
  res = assert(db.connector:query(fmt([[
    insert into routes (id, name, hosts, protocols, https_redirect_status_code, path_handling, service_id, ws_id)
    select
      gen_random_uuid() AS id,
      name,
      ARRAY[host] AS hosts,
      ARRAY['http', 'https'] AS protocols,
      426 AS https_redirect_status_code,
      'v0'::text AS path_handling,
      id AS service_id,
      '%s' AS ws_id
    from services
  ]], ws_id)))
  print(fmt("Inserted %s routes in %d seconds", res.affected_rows, calc_duration()))

  -- 03 Consumers
  res = assert(db.connector:query(fmt([[
    insert into consumers (id, username, custom_id, ws_id)
    select
      gen_random_uuid() AS id,
      i::text AS username,
      i::text AS custom_id,
      '%s' AS ws_id
    from generate_series(1, %d) s(i)
  ]], ws_id, NUM_PER_ENTITY)))
  print(fmt("Inserted %s consumers in %d seconds", res.affected_rows, calc_duration()))

  -- 04 Upstreams
  res = assert(db.connector:query(fmt([[
    insert into upstreams (id, name, algorithm, slots, ws_id)
    select
      gen_random_uuid() AS id,
      i::text AS name,
      'round-robin'::text AS algorithm,
      10000 AS slots,
      '%s' AS ws_id
    from generate_series(1, %d) s(i)
  ]], ws_id, NUM_PER_ENTITY)))
  print(fmt("Inserted %s upstreams in %d seconds", res.affected_rows, calc_duration()))

  -- 05 Targets
  res = assert(db.connector:query(fmt([[
    insert into targets (id, target, weight, upstream_id, ws_id)
    select
      gen_random_uuid() AS id,
      name AS target,
      100 AS weight,
      id AS upstream_id,
      '%s' AS ws_id
    from upstreams
  ]], ws_id)))
  print(fmt("Inserted %s targets in %d seconds", res.affected_rows, calc_duration()))

  -- 06 Plugins
  res = assert(db.connector:query(fmt([[
    insert into plugins (id, name, service_id, protocols, enabled, config, ws_id)
    select
      gen_random_uuid() AS id,
      'basic-auth'::text AS name,
      id AS service_id,
      ARRAY['http', 'https'] AS protocols,
      true AS enabled,
      '{}'::JSONB AS config,
      '%s' AS ws_id
    from services
  ]], ws_id)))
  print(fmt("Inserted %s plugins in %d seconds", res.affected_rows, calc_duration()))

  -- 07 Insert deletable services
  res = assert(db.connector:query(fmt([[
    insert into services (id, name, host, retries, port, connect_timeout, write_timeout, read_timeout, protocol, enabled, ws_id)
    select
      gen_random_uuid() AS id,
      CONCAT('delete_', i::text) AS name,
      CONCAT(i::text, '.delete.local') AS host,
      5 AS retries,
      80 AS port,
      60000 AS connect_timeout,
      60000 AS write_timeout,
      60000 AS read_timeout,
      'http' AS protocol,
      true AS enabled,
      '%s' AS ws_id
    from generate_series(1, %d) s(i)
  ]], ws_id, NUM_PER_ENTITY)))
  print(fmt("Inserted %s services in %d seconds", res.affected_rows, calc_duration()))

  -- 08 Insert deletable upstreams
  res = assert(db.connector:query(fmt([[
    insert into upstreams (id, name, algorithm, slots, ws_id)
    select
      gen_random_uuid() AS id,
      CONCAT('delete_', i::text) AS name,
      'round-robin'::text AS algorithm,
      10000 AS slots,
      '%s' AS ws_id
    from generate_series(1, %d) s(i)
  ]], ws_id, NUM_PER_ENTITY)))
  print(fmt("Inserted %s upstreams in %d seconds", res.affected_rows, calc_duration()))
end

-- Generate wrk Lua scripts for each entity
local gen_wrk_script = function(entity, action)
  local REQUEST_ID = "request_id"
  local qoute = stringx.quote_string
  local concat_lua_string = function(args)
    return table.concat(args, "..")
  end
  local mod_request_id = function(id)
    return fmt([[
      request_id = %s
    ]], id)
  end
  local gen_entity_path = function(entity1, entity2)
    local args = { qoute("/" .. entity1 .. "/"), REQUEST_ID }

    if entity2 then
      table.insert(args, qoute("/" .. entity2 .. "/"))
      table.insert(args, REQUEST_ID)
    end

    return concat_lua_string(args)
  end

  local gen_create_method = function(path, data)
    return fmt([[
      local path = %s
      local body = %s
      return wrk.format("POST", path, {["Content-Type"] = "application/x-www-form-urlencoded"}, body)
    ]], path, data)
  end

  local gen_update_method = function(path, data, method)
    method = method or "PUT"
    return fmt([[
      local path = %s
      local body = %s
      return wrk.format("%s", path, {["Content-Type"] = "application/x-www-form-urlencoded"}, body)
    ]], path, data, method)
  end

  local gen_get_method = function(path)
    return fmt([[
      local path = %s
      return wrk.format("GET", path)
    ]], path)
  end

  local gen_delete_method = function(path)
    return fmt([[
      local path = %s
      return wrk.format("DELETE", path)
    ]], path)
  end

  local request_scripts = {
    services = {
      create = gen_create_method(
        qoute("/services"),
        concat_lua_string({ qoute("name=perf_"), REQUEST_ID, qoute("&host=example.com&port=80&protocol=http") })
      ),
      get = gen_get_method(gen_entity_path("services")),
      update = gen_update_method(gen_entity_path("services"), qoute("host=konghq.com&port=99&protocol=https")),
      delete = mod_request_id(concat_lua_string({ qoute("delete_"), REQUEST_ID })) ..
          gen_delete_method(gen_entity_path("services")),
    },
    routes = {
      create = gen_create_method(
        concat_lua_string({ qoute("/services/"), REQUEST_ID, qoute("/routes") }),
        concat_lua_string({ qoute("name=perf_"), REQUEST_ID })
      ),
      get = gen_get_method(gen_entity_path("services", "routes")),
      update = gen_update_method(gen_entity_path("services", "routes"), qoute("paths[]=/test")),
      delete = gen_delete_method(gen_entity_path("services", "routes")),
    },
    consumers = {
      create = gen_create_method(
        qoute("/consumers"),
        concat_lua_string({ qoute("username=perf_"), REQUEST_ID })
      ),
      get = gen_get_method(gen_entity_path("consumers")),
      update = gen_update_method(
        gen_entity_path("consumers"),
        concat_lua_string({ qoute("username=test_"), REQUEST_ID })
      ),
      delete = gen_delete_method(gen_entity_path("consumers")),
    },
    upstreams = {
      create = gen_create_method(
        qoute("/upstreams"),
        concat_lua_string({ qoute("name=perf_"), REQUEST_ID })
      ),
      get = gen_get_method(gen_entity_path("upstreams")),
      update = gen_update_method(
        gen_entity_path("upstreams"),
        concat_lua_string({ qoute("name=test_"), REQUEST_ID })
      ),
      delete = mod_request_id(concat_lua_string({ qoute("delete_"), REQUEST_ID })) ..
          gen_delete_method(gen_entity_path("upstreams")),
    },
    targets = {
      create = gen_create_method(
        concat_lua_string({ qoute("/upstreams/"), REQUEST_ID, qoute("/targets") }),
        concat_lua_string({ qoute("target=perf_"), REQUEST_ID })
      ),
      get = gen_get_method(
        concat_lua_string({ qoute("/upstreams/"), REQUEST_ID, qoute("/targets") })
      ),
      update = gen_update_method(
        concat_lua_string({ qoute("/upstreams/"), REQUEST_ID, qoute("/targets") }),
        concat_lua_string({ qoute("target=test_"), REQUEST_ID }),
        'PATCH'
      ),
      delete = gen_delete_method(gen_entity_path("upstreams", "targets")),
    },
    -- no enabled
    plugins = {
      create = gen_create_method(
        concat_lua_string({ qoute("/services/"), REQUEST_ID, qoute("/plugins") }),
        qoute("name=key-auth")
      ),
      get = gen_get_method(
        concat_lua_string({ qoute("/services/"), REQUEST_ID, qoute("/key-auth") })
      ),
      update = gen_update_method(
        concat_lua_string({ qoute("/upstreams/"), REQUEST_ID, qoute("/targets") }),
        concat_lua_string({ qoute("target=test_"), REQUEST_ID }),
        'PATCH'
      ),
      delete = gen_delete_method(gen_entity_path("upstreams", "targets")),
    },
  }

  local script = [[
    local counter = 1
    local MAX_REQUESTS_PER_THREAD = ]] .. NUM_PER_ENTITY / WRK_THREADS .. [[

    function setup (thread)
      thread:set("id", counter)
      counter = counter + 1
    end

    function init ()
      requests = 0

      local thread_id = tonumber(wrk.thread:get("id"))
      base_id = (thread_id - 1) * MAX_REQUESTS_PER_THREAD
    end

    function request ()
      if requests >= MAX_REQUESTS_PER_THREAD then
        wrk.thread:stop()
      end

      requests = requests + 1
      local ]] .. REQUEST_ID .. [[ = base_id + requests

]] .. request_scripts[entity][action] .. [[

    end
    -- end request ]]

  return script
end

os.execute("mkdir -p output")

for _, mode in ipairs(KONG_MODES) do
for _, version in ipairs(versions) do

  describe(mode .. " mode #admin_api #crud", function()
    local helpers

    local feed_test_data = function ()
      -- clean up all tables
      -- skip migraitons
      print("Cleaning up all tables...")
      local _, db = helpers.get_db_utils("postgres", CORE_ENTITIES, nil, nil, true)
      gen_entities(db, CORE_ENTITIES)
    end

    local start_kong = function ()
      local kong_conf = {
        admin_listen = '0.0.0.0:8001',
        db_update_frequency = 10 + LOAD_DURATION, -- larger than LOAD_DURATION
        route_validation_strategy = 'off',
      }

      if mode == "hybrid" then
        print("Generating CP certificates...")
        perf.execute("kong hybrid gen_cert")

        kong_conf = tablex.merge(kong_conf, {
          cluster_cert = "/tmp/kong-hybrid-cert.pem",
          cluster_cert_key = "/tmp/kong-hybrid-key.pem",
          role = "control_plane",
          -- legacy_hybrid_protocol = 'on', -- disable wrpc
        })
      end

      print("Starting Kong...")
      local _, err = perf.start_kong(kong_conf, {
        ports = { 8001 }
      })
      if err then
        error(err)
      end
    end

    lazy_setup(function()
      helpers = perf.setup_kong(version)

      local _, err

      -- trigger migrations
      print("Running migrations...")
      _, err = perf.start_kong()
      if err then
        error(err)
      end
      perf.stop_kong()

      perf.start_worker()
    end)

    lazy_teardown(function()
      pcall(perf.stop_kong)
      perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)
    end)

    for _, entity in ipairs({ "services", "routes", "consumers" }) do
      for _, action in ipairs { "create", "get", "update", "delete" } do
        it(action .. " " .. entity, function()
          print("wrk script: ", gen_wrk_script(entity, action))
          local results = {}

          for i=1, REPEAT_PER_TEST + 1 do
            feed_test_data()
            start_kong()

            perf.start_load({
              uri = perf.get_admin_uri(),
              connections = 100,
              threads = WRK_THREADS,
              duration = LOAD_DURATION,
              script = gen_wrk_script(entity, action),
            })

            print("Waiting for load to finish...")

            local result = assert(perf.wait_result())
            table.insert(results, result)

            utils.print_and_save(fmt("### (%s) Result - %s - %s - try %s: \n%s", version, entity, action, i, result))
            perf.save_error_log(fmt("output/perf_testing_%s_%s_%s_%s.log", version, entity, action, i))

            perf.stop_kong() -- start/stop in each iterration to clear the cache
          end

          local combined_results = assert(perf.combine_results(results))

          utils.print_and_save("### Combined result:\n" .. combined_results)
        end)
      end
    end

  end)

end
end
