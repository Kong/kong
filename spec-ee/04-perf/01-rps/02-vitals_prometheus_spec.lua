-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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

local function print_and_save(s, path)
  os.execute("mkdir -p output")
  print(s)
  local f = io.open(path or "output/result.txt", "a")
  f:write(s)
  f:write("\n")
  f:close()
end

os.execute("mkdir -p output")

for _, version in ipairs(versions) do
  describe("perf test for Kong " .. version .. " #vitals", function()

    lazy_setup(function()
      local _ = perf.setup()

      perf.start_worker([[
        location = /test {
          return 200;
        }
      ]])

      perf.load_pgdump("spec/fixtures/perf/500services-each-4-routes.sql")
    end)

    before_each(function()
      perf.start_kong(version, {
        vitals = "on",
        vitals_strategy = "prometheus",
        vitals_statsd_address = "127.0.0.1:9125",
        vitals_tsdb_address = "127.0.0.1:9090",
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

      print_and_save("### Test Suite: " .. utils.get_test_descriptor())

      local results = {}
      for i=1,3 do
        perf.start_load({
          connections = 100,
          threads = 5,
          duration = LOAD_DURATION,
          script = wrk_script,
        })

        local result = assert(perf.wait_result())

        print_and_save(("### Result for Kong %s (run %d):\n%s"):format(version, i, result))
        results[i] = result
      end

      print_and_save(("### Combined result for Kong %s:\n%s"):format(version, assert(perf.combine_results(results))))

      perf.save_error_log("output/" .. utils.get_test_output_filename() .. ".log")
    end)
  end)
end
