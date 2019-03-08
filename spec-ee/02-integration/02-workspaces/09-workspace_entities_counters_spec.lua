local cjson       = require "cjson"
local helpers     = require "spec.helpers"


for _, strategy in helpers.each_strategy() do

  describe("Admin API #" .. strategy, function()
    local client

    local function any(t, p)
      return #(require("pl.tablex").filter(t, p)) > 0
    end

    local function post(path, body, headers, expected_status)
      headers = headers or {}
      if not headers["Content-Type"] then
        headers["Content-Type"] = "application/json"
      end

      if any(require("pl.tablex").keys(body), function(x) return x:match( "%[%]$") end) then
        headers["Content-Type"] = "application/x-www-form-urlencoded"
      end

      local res = assert(client:send{
        method = "POST",
        path = path,
        body = body or {},
        headers = headers
      })

      return cjson.decode(assert.res_status(expected_status or 201, res))
    end


    local function get(path, headers, expected_status)
      headers = headers or {}
      headers["Content-Type"] = "application/json"
      local res = assert(client:send{
        method = "GET",
        path = path,
        headers = headers
      })
      return cjson.decode(assert.res_status(expected_status or 200, res))
    end

    local function delete(path, body, headers, expected_status)
      headers = headers or {}
      headers["Content-Type"] = "application/json"
      local res = assert(client:send{
        method = "DELETE",
        path = path,
        headers = headers,
        body = body,
      })
      assert.res_status(expected_status or 204, res)
    end

    setup(function()
      helpers.get_db_utils(strategy)

      assert(helpers.start_kong{
        database = strategy,
        portal_auth = "basic-auth",  -- useful only for admin test
        mock_smtp = true,
      })
      client = assert(helpers.admin_client())
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    it("increments counter on entity_type and workspace", function()
      local res

      -- 2 workspaces (default and ws1), each with 1 consumer
      post("/workspaces", {name = "ws1"})
      local c1 = post("/consumers", {username = "first"})
      post("/ws1/consumers", {username = "bob"})

      res = get("/workspaces/ws1/meta")
      assert.equal(1, res.counts.consumers)

      res = get("/workspaces/default/meta")
      assert.equal(1, res.counts.consumers)

      -- share c1 with ws1
      post("/workspaces/ws1/entities", {entities = c1.id})

      -- ws1 has 2 consumers now
      res = get("/workspaces/ws1/meta")
      assert.equal(2, res.counts.consumers)

      -- default still has 1
      res = get("/workspaces/default/meta")
      assert.equal(1, res.counts.consumers)

      -- delete the one only in ws1
      delete("/ws1/consumers/bob" )
      local res = get("/workspaces/ws1/meta")
      assert.equal(1, res.counts.consumers)

      -- delete the shared one (multiple ws are deleted ok)
      delete("/ws1/consumers/" .. c1.id)
      res = get("/workspaces/ws1/meta")
      assert.equal(0, res.counts.consumers)

      res = get("/workspaces/default/meta")
      assert.equal(0, res.counts.consumers)

      -- delete ws1
      delete("/workspaces/ws1")
      get("/workspaces/default/meta")

      -- ws1 doesn't exist anymore
      get("/workspaces/ws1/meta", nil, 404)
    end)

    it("unshare decrements counts", function()
      post("/workspaces", {name = "ws1"})
      local c1 = post("/consumers", {username = "first"})
      -- share c1 with ws1
      post("/workspaces/ws1/entities", {entities = c1.id})

      -- ws1 has 1 consumer now
      local res = get("/workspaces/ws1/meta")
      assert.equal(1, res.counts.consumers)

      -- unshare c1 with ws1
      delete("/workspaces/ws1/entities", {entities = c1.id})
      -- ws1 has 0 consumers now
      local res = get("/workspaces/ws1/meta")
      assert.equal(0, res.counts.consumers)

      delete("/workspaces/ws1") --cleanup
    end)

    it("increments counters from new dao entities", function()
      post("/workspaces", {name = "ws1"})
      post("/ws1/services", {name = "s1", host = "s1.com"})
      local res = get("/workspaces/ws1/meta")
      assert.equals(1, res.counts.services)

      delete("/ws1/services/s1")
      res = get("/workspaces/ws1/meta")
      assert.equals(0, res.counts.services)
      delete("/workspaces/ws1") --cleanup
    end)

    it("returns 404 if we call from another workspace", function()
      post("/workspaces", {name = "ws1"})
      get("/ws1/workspaces/default/meta", nil, 404)
    end)

    it("#flaky admins nor developers do not modify consumers' counters", function()
      local before = get("/workspaces/default/meta").consumers
      post("/admins", {username = "foo", email = "email@email.com"}, nil, 200)
      post("/portal/developers", {username = "bar", email = "email@email2.com"})
      local after = get("/workspaces/default/meta").consumers
      assert.is_equal(before, after)

      delete("/admins/foo")
      delete("/portal/developers/email@email2.com")
      after = get("/workspaces/default/meta").consumers
      assert.is_equal(before, after)
    end)
  end)
end
