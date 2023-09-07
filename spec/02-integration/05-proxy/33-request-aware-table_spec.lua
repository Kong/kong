local helpers = require "spec.helpers"

local LOG_LEVELS = {
  "debug",
  "info",
  -- any other log level behaves the same as "info"
}


local function new_table()
  local client = helpers.proxy_client()
  local res = client:get("/", {
    query = {
      new_tab = true,
      clear = true,
    }
  })
  assert.response(res).has.status(200)
  assert.logfile().has.no.line("[error]", true)
  client:close()
end

for _, log_level in ipairs(LOG_LEVELS) do
  local concurrency_checks = log_level == "debug"

  for _, strategy in helpers.each_strategy() do
    describe("request aware table tests [#" .. strategy .. "] concurrency checks: " .. tostring(concurrency_checks), function()
      local client
      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "plugins",
          "routes",
          "services",
        }, {
          "request-aware-table"
        })

        local service = assert(bp.services:insert({
          url = helpers.mock_upstream_url
        }))

        local route = bp.routes:insert({
          service = service,
          paths = { "/" }
        })

        bp.plugins:insert({
          name = "request-aware-table",
          route = { id = route.id },
        })

        helpers.start_kong({
          database = strategy,
          plugins = "bundled, request-aware-table",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          log_level = log_level,
        })
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        helpers.clean_logfile()
        new_table()
        client = helpers.proxy_client()
      end)

      after_each(function()
        if client then
          client:close()
        end
      end)

      it("allows access when there are no race conditions", function()
        local res = client:get("/")
        assert.response(res).has.status(200)
        assert.logfile().has.no.line("[error]", true)
      end)

      it("denies access when there are race conditions and checks are enabled (else allows)", function()
        -- access from request 1 (don't clear)
        local r = client:get("/")
        assert.response(r).has.status(200)

        -- access from request 2
        r = client:get("/")
        if concurrency_checks then
          assert.logfile().has.line("race condition detected", true)
        else
          assert.response(r).has.status(200)
        end
      end)

      it("allows access when table is cleared between requests", function()
        -- access from request 1 (clear)
        local r = client:get("/", {
          query = {
            clear = true,
          }
        })
        assert.response(r).has.status(200)

        -- access from request 2 (clear)
        r = client:get("/", {
          query = {
            clear = true,
          }
        })
        assert.response(r).has.status(200)
        assert.logfile().has.no.line("[error]", true)

        -- access from request 3
        r = client:get("/")
        assert.response(r).has.status(200)
        assert.logfile().has.no.line("[error]", true)
      end)
    end)
  end
end