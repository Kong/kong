-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

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

  local headers = {
    ["Content-Type"] = "application/json"
  }

  describe("workspace_entity_counters", function()
    local admin_client

    before_each(function()
      bp = helpers.get_db_utils(strategy, {
        "workspaces",
      })
      assert(helpers.start_kong({
        database   = strategy,
      }))
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if admin_client then admin_client:close() end
      helpers.stop_kong(nil, true)
    end)

    it("can delete an empty workspace", function()
      local res = admin_client:post("/workspaces", {
        headers = headers,
        body    = {
          name = "ws1",
        },
      })
      assert.res_status(201, res)

      res = admin_client:delete("/workspaces/ws1", {
        headers = headers,
      })
      assert.res_status(204, res)
    end)

    -- Tests bug where cascade delete operations were not decrementing their workspace_entity_counters
    it("can delete a workspace with no more entity counters", function()
      local res = admin_client:post("/workspaces", {
        headers = headers,
        body    = {
          name = "ws1",
        },
      })
      assert.res_status(201, res)

      res = admin_client:post("/ws1/upstreams", {
        headers = headers,
        body = {
          name = "upstream1"
        }
      })
      assert.res_status(201, res)

      res = admin_client:post("/ws1/upstreams/upstream1/targets", {
        headers = headers,
        body = {
          target = "konghq.test:80"
        }
      })
      assert.res_status(201, res)

      res = admin_client:get("/workspaces/ws1/meta", {
        headers = headers,
      })
      local body = assert.res_status(200, res)
      local entity = cjson.decode(body)
      assert.equal(1, entity.counts.upstreams)
      assert.equal(1, entity.counts.targets)

      res = admin_client:delete("/ws1/upstreams/upstream1", {
        headers = headers,
      })
      assert.res_status(204, res)

      res = admin_client:get("/workspaces/ws1/meta", {
        headers = headers,
      })
      body = assert.res_status(200, res)
      entity = cjson.decode(body)
      assert.equal(0, entity.counts.upstreams)
      assert.equal(0, entity.counts.targets)

      res = admin_client:delete("/workspaces/ws1", {
        headers = headers,
      })
      assert.res_status(204, res)
    end)


  end)


end
