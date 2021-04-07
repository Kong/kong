local perf = require("spec.helpers.perf")

perf.set_log_level(ngx.DEBUG)
--perf.set_log_level(ngx.INFO)
--perf.use_driver("docker")
perf.use_driver("local")

-- local versions = { "2.2", "2.3" }
local versions = { "5fd75b2add2cbceb1e0576494d30b6c422b58626", "de8ef431d780985a78933bd89c813092db10f060" }

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
      assert(perf.stop_kong())
    end)

    lazy_teardown(function()
      perf.teardown()
    end)

    it("/test", function()
      assert(perf.start_load({
        path = "/test",
        connections = 1,
        threads = 1,
        duration = 10,
      }))

      ngx.sleep(10)

      local result = assert(perf.wait_result({
        timeout = 5
      }))

      print("### Result for kong ", version, ":\n", result, err)
    end)
  end)
end