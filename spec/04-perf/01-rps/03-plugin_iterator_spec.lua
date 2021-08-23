local perf = require("spec.helpers.perf")
local split = require("pl.stringx").split
local utils = require("spec.helpers.perf.utils")

perf.set_log_level(ngx.DEBUG)
--perf.set_retry_count(3)

local driver = os.getenv("PERF_TEST_DRIVER") or "docker"

if driver == "terraform" then
  perf.use_driver("terraform", {
    provider = "equinix-metal",
    tfvars = {
      -- Kong Benchmarking
      packet_project_id = os.getenv("PERF_TEST_PACKET_PROJECT_ID"),
      -- TODO: use an org token
      packet_auth_token = os.getenv("PERF_TEST_PACKET_AUTH_TOKEN"),
      -- packet_plan = "baremetal_1",
      -- packet_region = "sjc1",
      -- packet_os = "ubuntu_20_04",
    }
  })
else
  perf.use_driver(driver)
end

local versions = {}

local env_versions = os.getenv("PERF_TEST_VERSIONS")
if env_versions then
  versions = split(env_versions, ",")
end

local LOAD_DURATION = 20
local NUM_LOADS = 1

local function print_and_save(s, path)
  os.execute("mkdir -p output")
  print(s)
  local f = io.open(path or "output/result.txt", "a")
  f:write(s)
  f:write("\n")
  f:close()
end


for _, version in ipairs(versions) do
  for _, add_irrelevant in ipairs{false, true} do
    local termination_message = "performancetestperformancetestperformancetestperformancetest"

    describe("perf test for Kong " .. version .. " #plugin_iterator", function()
      local bp, another_service, another_route
      lazy_setup(function()
        local helpers = perf.setup()

        bp = helpers.get_db_utils("postgres", {
          "routes",
          "services",
          "plugins",
        })

        local upstream_uri = perf.start_upstream([[
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

        if add_irrelevant then
          -- those plugins doesn't run on current path, but does they affect plugin iterator?
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
        end

      end)

      before_each(function()
        perf.start_kong(version, {
          --kong configs
          log_level = "warn",
        })
      end)

      after_each(function()
        perf.stop_kong()
      end)

      lazy_teardown(function()
        perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)
      end)

      it(add_irrelevant and "#global_and_irrelevant" or "#global_only", function()
        print_and_save("### Test Suite: " .. utils.get_test_descriptor())

        local results = {}
        for i = 1, NUM_LOADS do
          perf.start_load({
            path = "/test",
            connections = 100,
            threads = 5,
            duration = LOAD_DURATION,
          })

          local result = assert(perf.wait_result())

          print_and_save(("### Result for Kong %s (run %d):\n%s"):format(version, i, result))
          results[i] = result
        end

        print_and_save(("### Combined result for Kong %s:\n%s"):format(version, assert(perf.combine_results(results))))

        perf.save_error_log("output/" .. utils.get_test_output_filename() .. ".log")
      end)

      --it("#global_and_irrelevant", function()
      --  print_and_save("### Test Suite: " .. utils.get_test_descriptor())
      --
      --  local results = {}
      --  for i=1,1 do
      --    perf.start_load({
      --      path = "/test",
      --      connections = 100,
      --      threads = 5,
      --      duration = LOAD_DURATION,
      --    })
      --
      --    local result = assert(perf.wait_result())
      --
      --    print_and_save(("### Result for Kong %s (run %d):\n%s"):format(version, i, result))
      --    results[i] = result
      --  end
      --
      --  print_and_save(("### Combined result for Kong %s:\n%s"):format(version, assert(perf.combine_results(results))))
      --
      --  perf.save_error_log("output/" .. utils.get_test_output_filename() .. ".log")
      --end)

    end)
  end

end
