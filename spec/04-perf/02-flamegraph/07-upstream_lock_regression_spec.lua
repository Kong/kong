local shell = require "resty.shell"
local perf = require("spec.helpers.perf")
local split = require("pl.stringx").split
local utils = require("spec.helpers.perf.utils")
local workspaces = require "kong.workspaces"
local fmt = string.format

perf.setenv("PERF_TEST_SEPERATE_DB_NODE", "1")

perf.use_defaults()

perf.enable_charts(false) -- don't generate charts, we need flamegraphs only

local versions = {}

local env_versions = os.getenv("PERF_TEST_VERSIONS")
if env_versions then
  versions = split(env_versions, ",")
end

local LOAD_DURATION = 180

shell.run("mkdir -p output", nil, 0)

local function patch(helpers, patch_interval)
  local status, bsize
  local starting = ngx.now()
  for i =1, LOAD_DURATION, 1 do
    if i % patch_interval == patch_interval - 1 then
      ngx.update_time()
      local s = ngx.now()
      local admin_client = helpers.admin_client()
      local pok, pret, _ = pcall(admin_client.patch, admin_client, "/routes/1", {
        body = {
          tags = { tostring(ngx.now()) }
        },
        headers = { ["Content-Type"] = "application/json" },
      })

      if pok then
        status = pret.status
        local body, _ = pret:read_body()
        if body then
          bsize = #body
        end
      else
        print("error calling admin api " .. pret)
      end

      ngx.update_time()
      admin_client:close()
      print(string.format("PATCH /routes scrape takes %fs (read %s, status %s)", ngx.now() - s, bsize, status))
    end
    if ngx.now() - starting > LOAD_DURATION then
      break
    end
    ngx.sleep(1)
  end
end

for _, version in ipairs(versions) do
-- for _, patch_interval in ipairs({5, 10, 15, 99999}) do
for _, upstream_count in ipairs({100, 5000}) do
-- for _, do_patch in ipairs({true, false}) do
local do_patch = false
  describe("perf test for Kong " .. version .. " #upstream_lock_regression " .. upstream_count .. " upstreams", function()
    local helpers

    lazy_setup(function()
      helpers = perf.setup_kong(version)

      local upstream_uri = perf.start_worker([[
        location = /test {
          return 200;
        }
      ]])

      local bp, db = helpers.get_db_utils("postgres", {
        "services",
        "routes",
        "upstreams",
      }, nil, nil, true)

      local ws_id = workspaces.get_workspace().id
      -- 01 Services
      assert(db.connector:query(fmt([[
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
      ]], ws_id, upstream_count)))

      -- 02 Routes
      assert(db.connector:query(fmt([[
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


      -- 04 Upstreams
      assert(db.connector:query(fmt([[
        insert into upstreams (id, name, algorithm, slots, ws_id, hash_on, hash_fallback, hash_on_cookie_path)
        select
          gen_random_uuid() AS id,
          host AS name,
          'round-robin'::text AS algorithm,
          10000 AS slots,
          '%s' AS ws_id,
          'none'::text AS hash_on,
          'none'::text AS hash_fallback,
          '/'::text AS hash_on_cookie_path
        from services
      ]], ws_id)))

      for _, target in ipairs({
        "127.0.0.1:8001",
        "127.0.0.1:8002",
        "127.0.0.1:8003",
        "127.0.0.1:8004"
      }) do
        -- 05 Targets
        assert(db.connector:query(fmt([[
          insert into targets (id, target, weight, upstream_id, ws_id)
          select
            gen_random_uuid() AS id,
            '%s'::text AS target,
            100 AS weight,
            id AS upstream_id,
            '%s' AS ws_id
          from upstreams
        ]], target, ws_id)))
      end

      local service = bp.services:insert {
        url = upstream_uri .. "/test",
      }

      bp.routes:insert {
        paths = { "/s1-r1" },
        service = service,
        strip_path = true,
      }
    end)

    before_each(function()
      local _, err
      _, err = perf.start_kong({
        proxy_listen = "off",
        role = "control_plane",
        vitals = "off",
        cluster_cert = "/tmp/kong-hybrid-cert.pem",
        cluster_cert_key = "/tmp/kong-hybrid-key.pem",
        mem_cache_size = "1024m",
      }, {
        name = "cp",
        ports = { 8001 },
      })
      assert(err == nil, err)

      _, err = perf.start_kong({
        admin_listen = "off",
        role = "data_plane",
        database = "off",
        vitals = "off",
        cluster_cert = "/tmp/kong-hybrid-cert.pem",
        cluster_cert_key = "/tmp/kong-hybrid-key.pem",
        cluster_control_plane = "cp:8005",
        mem_cache_size = "1024m",
        nginx_worker_processes = 1,
      }, {
        name = "dp",
        ports = { 8000 },
      })
      assert(err == nil, err)

      -- wait for hybrid mode sync
      ngx.sleep(10)
    end)

    after_each(function()
      perf.stop_kong()
    end)

    lazy_teardown(function()
      perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)
    end)

    it(do_patch and "patch every 15s" or "no patch", function()

      perf.start_stapxx("lj-lua-stacks.sxx", "-D MAXMAPENTRIES=1000000 --arg time=" .. LOAD_DURATION, {
        name = "dp"
      })

      perf.start_load({
        connections = 100,
        threads = 5,
        duration = LOAD_DURATION,
        path = "/s1-r1",
      })

      if do_patch then
        patch(helpers, 15)
      end

      local result = assert(perf.wait_result())

      print(("### Result for Kong %s:\n%s"):format(version, result))

      perf.generate_flamegraph(
        "output/" .. utils.get_test_output_filename() .. ".svg",
        "Flame graph for Kong " .. utils.get_test_descriptor()
      )

      perf.save_error_log("output/" .. utils.get_test_output_filename() .. ".log")
    end)
  end)
end
end
