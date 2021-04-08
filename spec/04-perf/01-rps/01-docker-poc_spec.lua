local perf = require("spec.helpers.perf")

perf.set_log_level(ngx.DEBUG)
--perf.set_log_level(ngx.INFO)
--perf.set_retry_count(3)

-- perf.use_driver("docker")
-- local versions = { "2.3.2", "2.3.3" }

-- perf.use_driver("local")
-- local versions = { "5fd75b2add2cbceb1e0576494d30b6c422b58626", "de8ef431d780985a78933bd89c813092db10f060" }

perf.use_driver("terraform", {
  provider = "equinix-metal",
  tfvars = {
    -- Kong Benchmarking
    packet_project = "?",
    -- TODO: use an org token
    packet_auth_token = "?",
    -- packet_plan = "baremetal_1",
    -- packet_region = "sjc1",
    -- packet_os = "ubuntu_20_04",
  }
})
local versions = { "2.3.2", "2.3.3" }

for _, version in ipairs(versions) do
  describe("perf test for Kong " .. version, function()
    lazy_setup(function()
      local helpers = perf.setup()

      local bp, db = helpers.get_db_utils(strategy, {
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
      perf.start_load({
        path = "/test",
        connections = 1000,
        threads = 5,
        duration = 10,
      })

      ngx.sleep(10)

      local result = assert(perf.wait_result({
        timeout = 5
      }))

      print("### Result for kong ", version, ":\n", result, err)
    end)
  end)
end