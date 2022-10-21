local perf = require("spec.helpers.perf")
local split = require("pl.stringx").split
local utils = require("spec.helpers.perf.utils")

perf.use_defaults()

local versions = {}

local env_versions = os.getenv("PERF_TEST_VERSIONS")
if env_versions then
  versions = split(env_versions, ",")
end

local LOAD_DURATION = os.getenv("PERF_TEST_LOAD_DURATION") or 30


for _, version in ipairs(versions) do
  local helpers, upstream_uris

  describe("perf test for Kong " .. version .. " #balancer", function()
    local bp
    lazy_setup(function()
      helpers = perf.setup_kong(version)

      bp = helpers.get_db_utils("postgres", {
        "routes",
        "services",
        "upstreams",
        "targets",
      }, nil, nil, true)

      upstream_uris = perf.start_worker([[
      location = /test {
        return 200;
      }
      ]], 10)


      -- plain Service
      local service = bp.services:insert {
        url = upstream_uris[1] .. "/test",
      }

      bp.routes:insert {
        paths = { "/no-upstream" },
        service = service,
        strip_path = true,
      }

      -- upstream with 1 target
      local upstream = assert(bp.upstreams:insert {
        name = "upstream1target",
      })

      assert(bp.targets:insert({
        upstream = { id = upstream.id, },
        target = upstream_uris[1]:match("[%d%.]+:%d+"),
      }))

      local service = bp.services:insert {
        url = "http://upstream1target/test",
      }

      bp.routes:insert {
        paths = { "/upstream1target" },
        service = service,
        strip_path = true,
      }

      -- upstream with 10 targets
      local upstream = assert(bp.upstreams:insert {
        name = "upstream10targets",
      })

      for i=1,10 do
        assert(bp.targets:insert({
          upstream = { id = upstream.id, },
          target = upstream_uris[i]:match("[%d%.]+:%d+"),
          weight = i*5,
        }))
      end

      local service = bp.services:insert {
        url = "http://upstream10targets/test",
      }

      bp.routes:insert {
        paths = { "/upstream10targets" },
        service = service,
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

    it("#no_upstream", function()
      utils.print_and_save("### Test Suite: " .. utils.get_test_descriptor())

      local results = {}
      for i=1,3 do
        perf.start_load({
          path = "/no-upstream",
          connections = 100,
          threads = 5,
          duration = LOAD_DURATION,
        })


        local result = assert(perf.wait_result())

        utils.print_and_save(("### Result for Kong %s (run %d):\n%s"):format(version, i, result))
        results[i] = result
      end

      utils.print_and_save(("### Combined result for Kong %s:\n%s"):format(version, assert(perf.combine_results(results))))

      perf.save_error_log("output/" .. utils.get_test_output_filename() .. ".log")
    end)

    it("#upstream_1_target", function()
      utils.print_and_save("### Test Suite: " .. utils.get_test_descriptor())

      local results = {}
      for i=1,3 do
        perf.start_load({
          path = "/upstream1target",
          connections = 100,
          threads = 5,
          duration = LOAD_DURATION,
        })

        local result = assert(perf.wait_result())

        utils.print_and_save(("### Result for Kong %s (run %d):\n%s"):format(version, i, result))
        results[i] = result
      end

      utils.print_and_save(("### Combined result for Kong %s:\n%s"):format(version, assert(perf.combine_results(results))))

      perf.save_error_log("output/" .. utils.get_test_output_filename() .. ".log")
    end)

    it("#upstream_10_targets", function()
      utils.print_and_save("### Test Suite: " .. utils.get_test_descriptor())

      local results = {}
      for i=1,3 do
        perf.start_load({
          path = "/upstream10targets",
          connections = 100,
          threads = 5,
          duration = LOAD_DURATION,
        })

        local result = assert(perf.wait_result())

        utils.print_and_save(("### Result for Kong %s (run %d):\n%s"):format(version, i, result))
        results[i] = result
      end

      utils.print_and_save(("### Combined result for Kong %s:\n%s"):format(version, assert(perf.combine_results(results))))

      perf.save_error_log("output/" .. utils.get_test_output_filename() .. ".log")
    end)

    it("#balancer_rebuild", function()
      local exiting = false
      math.randomseed(os.time())
      assert(ngx.timer.at(0, function()

        while not exiting do
          local admin_client = assert(helpers.admin_client())
          local target = upstream_uris[math.floor(math.random()*10)+1]:match("[%d%.]+:%d+")
          local res = admin_client:patch("/upstreams/upstream10targets/targets/" .. target, {
            body = {
              weight = math.floor(math.random()*50)
            },
            headers = { ["Content-Type"] = "application/json" },
          })
          assert(res.status == 200, "PATCH targets returns non-200 response: " .. res.status)
          admin_client:close()
          ngx.sleep(3)
        end
      end))

      utils.print_and_save("### Test Suite: " .. utils.get_test_descriptor())

      local results = {}
      for i=1,3 do
        perf.start_load({
          path = "/upstream10targets",
          connections = 100,
          threads = 5,
          duration = LOAD_DURATION,
        })

        local result = assert(perf.wait_result())

        utils.print_and_save(("### Result for Kong %s (run %d):\n%s"):format(version, i, result))
        results[i] = result
      end
      exiting = true

      utils.print_and_save(("### Combined result for Kong %s:\n%s"):format(version, assert(perf.combine_results(results))))

      perf.save_error_log("output/" .. utils.get_test_output_filename() .. ".log")

    end)

  end)

end
