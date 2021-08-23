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

local LOAD_DURATION = 60

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

local function print_and_save(s, path)
  os.execute("mkdir -p output")
  print(s)
  local f = io.open(path or "output/result.txt", "a")
  f:write(s)
  f:write("\n")
  f:close()
end

describe("perf test #baseline", function()
  local upstream_uri
  lazy_setup(function()
    perf.setup()

    upstream_uri = perf.start_upstream([[
      location = /test {
        return 200;
      }
      ]])
  end)

  lazy_teardown(function()
    perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)
  end)

  it("upstream directly", function()
    local results = {}
    for i=1,3 do
      perf.start_load({
        uri = upstream_uri,
        path = "/test",
        connections = 100,
        threads = 5,
        duration = LOAD_DURATION,
      })

      local result = assert(perf.wait_result())

      print_and_save(("### Result for upstream directly (run %d):\n%s"):format(i, result))
      results[i] = result
    end

    print_and_save("### Combined result for upstream directly:\n" .. assert(perf.combine_results(results)))
  end)
end)

for _, version in ipairs(versions) do

  describe("perf test for Kong " .. version .. " #simple #no_plugins", function()
    local bp
    lazy_setup(function()
      local helpers = perf.setup()

      bp = helpers.get_db_utils("postgres", {
        "routes",
        "services",
      })

      local upstream_uri = perf.start_upstream([[
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
      perf.start_kong(version, {
        --kong configs
      })
    end)

    after_each(function()
      perf.stop_kong()
    end)

    lazy_teardown(function()
      perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)
    end)

    it("#single_route", function()
      print_and_save("### Test Suite: " .. utils.get_test_descriptor())

      local results = {}
      for i=1,3 do
        perf.start_load({
          path = "/s1-r1",
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

  describe("perf test for Kong " .. version .. " #simple #key-auth", function()
    local bp
    lazy_setup(function()
      local helpers = perf.setup()

      bp = helpers.get_db_utils("postgres", {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      })

      local upstream_uri = perf.start_upstream([[
        location = /test {
          return 200;
        }
        ]])

        for i=1, CONSUMER_COUNT do
          local name = "consumer-" .. i
          local consumer = bp.consumers:insert {
            username = name,
          }

          bp.keyauth_credentials:insert {
            key      = name,
            consumer = consumer,
          }
        end

        for i=1, SERVICE_COUNT do
          local service = bp.services:insert {
            url = upstream_uri .. "/test",
          }

          bp.plugins:insert {
            name = "key-auth",
            service = service,
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
      perf.start_kong(version, {
        --kong configs
      })
    end)

    after_each(function()
      perf.stop_kong()
    end)

    lazy_teardown(function()
      perf.teardown(os.getenv("PERF_TEST_TEARDOWN_ALL") or false)
    end)

    it(SERVICE_COUNT .. " services each has " .. ROUTE_PER_SERVICE .. " routes " ..
      "with key-auth, " .. CONSUMER_COUNT .. " consumers", function()

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