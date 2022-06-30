local perf = require("spec.helpers.perf")
local split = require("pl.stringx").split
local utils = require("spec.helpers.perf.utils")

perf.enable_charts(false) -- don't generate charts, we need flamegraphs only
perf.use_defaults()

local versions = {}

local env_versions = os.getenv("PERF_TEST_VERSIONS")
if env_versions then
  versions = split(env_versions, ",")
end

local LOAD_DURATION = 180


for _, version in ipairs(versions) do
  local termination_message = "performancetestperformancetestperformancetestperformancetest"

  describe("perf test for Kong " .. version .. " #plugin_iterator", function()
    local bp, another_service, another_route
    lazy_setup(function()
      local helpers = perf.
      zsetup_kong(version)

      bp = helpers.get_db_utils("postgres", {
        "routes",
        "services",
        "plugins",
      }, nil, nil, true)

      local upstream_uri = perf.start_worker([[
        location = /test {
          return 200;
        }
      ]])

      local service = bp.services:insert {
        url = upstream_uri .. "/test",
      }

      bp.plugins:insert {
        name = "request-termination",
        config = {
          status_code = 200,
          message = termination_message,
        }
      }

      bp.routes:insert {
        paths = { "/test" },
        service = service,
        strip_path = true,
      }

      another_service = bp.services:insert {
        url = upstream_uri .. "/another",
      }

      another_route = bp.routes:insert {
        paths = { "/another" },
        service = another_service,
        strip_path = true,
      }

    end)

    before_each(function()
      perf.start_kong({
        --kong configs
      })
    end)

    after_each(function()
      perf.stop_kong()
    end)

    lazy_teardown(function()
      perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)
    end)

    it("#global_only", function()

      perf.start_stapxx("lj-lua-stacks.sxx", "-D MAXMAPENTRIES=1000000 --arg time=" .. LOAD_DURATION)

      perf.start_load({
        path = "/test",
        connections = 100,
        threads = 5,
        duration = LOAD_DURATION,
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

    it("#global_and_irrelevant", function()
      -- those plugins doesn't run on current path, but does they affect plugin iterrator?
      bp.plugins:insert {
        name = "request-termination",
        service = another_service,
        config = {
          status_code = 200,
          message = termination_message,
        }
      }

      bp.plugins:insert {
        name = "request-termination",
        route = another_route,
        config = {
          status_code = 200,
          message = termination_message,
        }
      }

      perf.start_stapxx("lj-lua-stacks.sxx", "-D MAXMAPENTRIES=1000000 --arg time=" .. LOAD_DURATION)

      perf.start_load({
        path = "/test",
        connections = 100,
        threads = 5,
        duration = LOAD_DURATION,
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