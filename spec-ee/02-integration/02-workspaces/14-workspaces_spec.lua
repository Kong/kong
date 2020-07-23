local helpers = require "spec.helpers"

local proxy_client, bp

for _, strategy in helpers.each_strategy() do
  describe("plugin runloop with multiple workspaces", function()

    before_each(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "workspaces",
      }, {
        "rewriter",
      })
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
      helpers.stop_kong(nil, true)
    end)

    it("only runs plugins on default ws in early phases. not in ws1", function()
      local ws1 = assert(bp.workspaces:insert({ name = "ws1" }))

      local s = bp.services:insert_ws(nil, ws1)
      bp.routes:insert_ws({
        paths = {"/"},
        service = s
      }, ws1)

      bp.plugins:insert_ws({
        name = "rewriter",
        -- service = s,
        config = { value = "1" }
      }, ws1)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      proxy_client = helpers.proxy_client()

      local res = proxy_client:get("/")
      assert.res_status(200, res)
      assert.request(res).has.no.header("rewriter")
    end)

    it("only runs plugins on default ws in early phases", function()
      -- Phases where the ws can't be known yet (pre route-matching),
      -- we only run through the plugins in the default ws.

      local s = bp.services:insert()
      bp.routes:insert({
        paths = {"/"},
        service = s
      })

      bp.plugins:insert({
        name = "rewriter",
        -- service = s,
        config = { value = "1" }
      })

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      proxy_client = helpers.proxy_client()

      local res = proxy_client:get("/")
      assert.res_status(200, res)
      local value = assert.request(res).has.header("rewriter")
      assert.equal("1", value)
    end)

    it("only runs plugins on default ws in early phases, not if the plugin is associated to a service (not global)", function()
      -- Phases where the ws can't be known yet (pre route-matching),
      -- we only run through the plugins in the default ws.

      local s = bp.services:insert()
      bp.routes:insert({
        paths = {"/"},
        service = s
      })

      bp.plugins:insert({
        name = "rewriter",
        service = s,
        config = { value = "1" }
      })

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      proxy_client = helpers.proxy_client()

      local res = proxy_client:get("/")
      assert.res_status(200, res)
      assert.request(res).has.no.header("rewriter")
    end)
  end)

end
