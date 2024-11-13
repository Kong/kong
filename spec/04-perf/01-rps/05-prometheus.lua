local perf = require("spec.helpers.perf")
local split = require("pl.stringx").split
local utils = require("spec.helpers.perf.utils")

perf.use_defaults()

local versions = {}

local env_versions = os.getenv("PERF_TEST_VERSIONS")
if env_versions then
  versions = split(env_versions, ",")
end

local LOAD_DURATION = 30

local SERVICE_COUNT = 500
local ROUTE_PER_SERVICE = 4


local wrk_script = [[
  --This script is originally from https://github.com/Kong/miniperf
  math.randomseed(os.time()) -- Generate PRNG seed
  local rand = math.random -- Cache random method
  -- Get env vars for consumer and api count or assign defaults
  local service_count = ]] .. SERVICE_COUNT .. [[
  local route_per_service = ]] .. ROUTE_PER_SERVICE .. [[
  function request()
    -- generate random URLs, some of which may yield non-200 response codes
    local random_service = rand(service_count)
    local random_route = rand(route_per_service)
    -- Concat the url parts
    -- url_path = string.format("/s%s-r%s?apikey=consumer-%s", random_service, random_route, random_consumer)
    url_path = string.format("/s%s-r%s", random_service, random_route)
    -- Return the request object with the current URL path
    return wrk.format(nil, url_path, headers)
  end
]]

local function scrape(helpers, scrape_interval)
  local starting = ngx.now()
  for i =1, LOAD_DURATION, 1 do
    if i % scrape_interval == scrape_interval - 1 then
      ngx.update_time()
      local s = ngx.now()
      local admin_client = helpers.admin_client()
      local pok, pret, _ = pcall(admin_client.get, admin_client, "/metrics")
      local bsize, status = 0, 0
      local lat = ""
      if pok then
        status = pret.status
        local body, _ = pret:read_body()
        if body then
          bsize = #body
          lat = string.match(body, "###.+###")
        end
      end
      ngx.update_time()
      admin_client:close()
      print(string.format("/metrics scrape takes %fs (read %s, status %s, %s)", ngx.now() - s, bsize, status, lat))
    end
    if ngx.now() - starting > LOAD_DURATION then
      break
    end
    ngx.sleep(1)
  end
end

for _, version in ipairs(versions) do
-- for _, scrape_interval in ipairs({5, 10, 15, 99999}) do
for _, scrape_interval in ipairs({10}) do
  describe("perf test for Kong " .. version .. " #prometheus scrapes every " .. scrape_interval .. "s", function()
    local helpers

    lazy_setup(function()
      helpers = perf.setup_kong(version)

      perf.start_worker([[
        location = /test {
          return 200;
        }
      ]])

      local bp = helpers.get_db_utils("postgres", {
        "plugins",
      }, nil, nil, true)

      perf.load_pgdump("spec/fixtures/perf/500services-each-4-routes.sql")
      -- XXX: hack the workspace since we update the workspace in dump
      -- find a better way to automatically handle this
      ngx.ctx.workspace = "dde1a96f-1d2f-41dc-bcc3-2c393ec42c65"

      bp.plugins:insert {
        name = "prometheus",
      }
    end)

    before_each(function()
      perf.start_kong({
        vitals = "off",
        nginx_http_lua_shared_dict = 'prometheus_metrics 1024M',
        --kong configs
      })
    end)

    after_each(function()
      perf.stop_kong()
    end)

    lazy_teardown(function()
      perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)
    end)

    it(SERVICE_COUNT .. " services each has " .. ROUTE_PER_SERVICE .. " routes", function()

      utils.print_and_save("### Test Suite: " .. utils.get_test_descriptor())

      local results = {}
      for i=1,3 do
        perf.start_load({
          connections = 100,
          threads = 5,
          duration = LOAD_DURATION,
          script = wrk_script,
        })

        scrape(helpers, scrape_interval)

        local result = assert(perf.wait_result())

        utils.print_and_save(("### Result for Kong %s (run %d):\n%s"):format(version, i, result))
        results[i] = result
      end

      utils.print_and_save(("### Combined result for Kong %s:\n%s"):format(version, assert(perf.combine_results(results))))

      perf.save_error_log("output/" .. utils.get_test_output_filename() .. ".log")
    end)
  end)

  describe("perf test for Kong " .. version .. " #prometheus not enabled scarpe every " .. scrape_interval .. "s", function()
    local helpers

    lazy_setup(function()
      helpers = perf.setup_kong(version)

      perf.start_worker([[
        location = /test {
          return 200;
        }
      ]])

      -- run migrations
      helpers.get_db_utils("postgres", {
        "plugins",
      })

      perf.load_pgdump("spec/fixtures/perf/500services-each-4-routes.sql")
    end)

    before_each(function()
      perf.start_kong({
        vitals = "off",
        --kong configs
      })
    end)

    after_each(function()
      perf.stop_kong()
    end)

    lazy_teardown(function()
      perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)
    end)

    it(SERVICE_COUNT .. " services each has " .. ROUTE_PER_SERVICE .. " routes", function()

      utils.print_and_save("### Test Suite: " .. utils.get_test_descriptor())

      local results = {}
      for i=1,3 do
        perf.start_load({
          connections = 100,
          threads = 5,
          duration = LOAD_DURATION,
          script = wrk_script,
        })

        scrape(helpers, scrape_interval)

        local result = assert(perf.wait_result())

        utils.print_and_save(("### Result for Kong %s (run %d):\n%s"):format(version, i, result))
        results[i] = result
      end

      utils.print_and_save(("### Combined result for Kong %s:\n%s"):format(version, assert(perf.combine_results(results))))

      perf.save_error_log("output/" .. utils.get_test_output_filename() .. ".log")
    end)
  end)
end
end
