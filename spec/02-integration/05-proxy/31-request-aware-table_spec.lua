local helpers = require "spec.helpers"


local function clear_table(client, checks)
  local res = client:get("/", {
    query = {
      checks = checks,
      clear = true,
    }
  })
  assert.response(res).has.status(200)
  assert.logfile().has.no.line("[error]", true)
end

for _, checks in ipairs({ true, false }) do
for _, strategy in helpers.each_strategy() do
  describe("request aware table tests [#" .. strategy .. "] .. checks=" .. tostring(checks), function()
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
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      helpers.clean_logfile()
      client = helpers.proxy_client()
      clear_table(client, checks)
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("with concurrency check enabled", function()
      it("allows access when there are no race conditions", function()
        local res = client:get("/", {
          query = {
            checks = checks,
          }
        })
        assert.response(res).has.status(200)
        assert.logfile().has.no.line("[error]", true)
      end)
      it("denies access when there are race conditions and checks are enabled", function()
        -- access from request 1 (don't clear)
        local ok, r = pcall(client.get, client, "/", {
          query = {
            checks = checks,
          },
        })
        assert(ok)
        assert.response(r).has.status(200)

        -- access from request 2
        ok, r = pcall(client.get, client, "/", {
          query = {
            checks = checks,
          },
        })
        if checks then
          assert(not ok)
          assert.logfile().has.line("race condition detected", true)
        else
          assert(ok)
          assert.response(r).has.status(200)
        end
      end)
      it("allows access when table is cleared between requests", function()
        -- access from request 1 (clear)
        local r = client:get("/", {
          query = {
            checks = checks,
            clear = true,
          },
        })
        assert.response(r).has.status(200)

        -- access from request 2
        r = client:get("/", {
          query = {
            checks = checks,
          },
        })
        assert.response(r).has.status(200)
        assert.logfile().has.no.line("[error]", true)
      end)
    end)
  end)
end
end