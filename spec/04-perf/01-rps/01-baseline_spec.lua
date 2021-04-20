local perf = require("spec.helpers.perf")

perf.set_log_level(ngx.DEBUG)
--perf.set_retry_count(3)

local driver = os.getenv("KONG_PERF_DRIVER") or "docker"

if driver == "terraform" then
  perf.use_driver("terraform", {
    provider = "equinix-metal",
    tfvars = {
      -- Kong Benchmarking
      packet_project_id = os.getenv("PACKET_PROJECT_ID"),
      -- TODO: use an org token
      packet_auth_token = os.getenv("PACKET_AUTH_TOKEN"),
      -- packet_plan = "baremetal_1",
      -- packet_region = "sjc1",
      -- packet_os = "ubuntu_20_04",
    }
  })
else
  perf.use_driver(driver)
end

local versions = { "2.3.3", "2.4.0" }

for _, version in ipairs(versions) do
  describe("perf test for Kong " .. version, function()
    local bp, db
    lazy_setup(function()
      local helpers = perf.setup()

      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      })

      local consumer = bp.consumers:insert({
        username = "bob"
      }, { nulls = true })

      local upstream_uri = perf.start_upstream([[
      location = /test {
        return 200;
      }
      ]])

      local service = bp.services:insert {
        url = upstream_uri,
      }

      local route1 = bp.routes:insert {
        paths = { "/test" },
        service = service,
        strip_path = false,
      }
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
      perf.teardown()
      -- terraform teardown all infra
      -- perf.teardown(true)
    end)

    it("/test", function()
      local results = {}
      for i=1,3 do
        perf.start_load({
          path = "/test",
          connections = 1000,
          threads = 5,
          duration = 10,
        })

        ngx.sleep(10)

        local result = assert(perf.wait_result())

        print(("### Result for kong %s (run %d):\n%s"):format(version, i, result))
        results[i] = result
      end

      print("### Combined results:\n" .. assert(perf.combine_results(results)))
    end)
  end)
end