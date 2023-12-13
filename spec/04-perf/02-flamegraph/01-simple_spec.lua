local perf = require("spec.helpers.perf")
local split = require("pl.stringx").split
local utils = require("spec.helpers.perf.utils")
local shell = require "resty.shell"

perf.enable_charts(false) -- don't generate charts, we need flamegraphs only
perf.use_defaults()

local versions = {}

local env_versions = os.getenv("PERF_TEST_VERSIONS")
if env_versions then
  versions = split(env_versions, ",")
end

local LOAD_DURATION = 180

local SERVICE_COUNT = 10
local ROUTE_PER_SERVICE = 10
local CONSUMER_COUNT = 100

local wrk_script = [[
  --This script is originally from https://github.com/Kong/miniperf
  math.randomseed(os.time()) -- Generate PRNG seed
  local rand = math.random -- Cache random method
  -- Get env vars for consumer and api count or assign defaults
  local consumer_count = ]] .. CONSUMER_COUNT .. [[
  local service_count = ]] .. SERVICE_COUNT .. [[
  local route_per_service = ]] .. ROUTE_PER_SERVICE .. [[
  function request()
    -- generate random URLs, some of which may yield non-200 response codes
    local random_consumer = rand(consumer_count)
    local random_service = rand(service_count)
    local random_route = rand(route_per_service)
    -- Concat the url parts
    url_path = string.format("/s%s-r%s?apikey=consumer-%s", random_service, random_route, random_consumer)
    -- Return the request object with the current URL path
    return wrk.format(nil, url_path, headers)
  end
]]

shell.run("mkdir -p output", nil, 0)

for _, version in ipairs(versions) do
  describe("perf test for Kong " .. version .. " #simple #no_plugins", function()
    local bp
    lazy_setup(function()
      local helpers = perf.setup_kong(version)

      bp = helpers.get_db_utils("postgres", {
        "routes",
        "services",
      }, nil, nil, true)

      local upstream_uri = perf.start_worker([[
      location = /test {
        return 200;
      }
      ]])

      for i=1, SERVICE_COUNT do
        local service = bp.services:insert {
          url = upstream_uri .. "/test",
        }

        for j=1, ROUTE_PER_SERVICE do
          bp.routes:insert {
            paths = { string.format("/s%d-r%d", i, j) },
            service = service,
            strip_path = true,
          }
        end
      end
    end)

    before_each(function()
      perf.start_kong({
        nginx_worker_processes = 1,
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
      perf.start_stapxx("lj-lua-stacks.sxx", "-D MAXMAPENTRIES=1000000 --arg time=" .. LOAD_DURATION)

      perf.start_load({
        connections = 100,
        threads = 5,
        duration = LOAD_DURATION,
        script = wrk_script,
      })

      ngx.sleep(LOAD_DURATION)

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
