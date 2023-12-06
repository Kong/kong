-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson       = require "cjson"
local helpers     = require "spec.helpers"


for _, strategy in helpers.each_strategy() do

  describe("Admin API #" .. strategy, function()
    local client

    local function any(t, p)
      return #(require("pl.tablex").filter(t, p)) > 0
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

    local function put(path, body, headers, expected_status)
      headers = headers or {}
      if not headers["Content-Type"] then
        headers["Content-Type"] = "application/json"
      end

      if any(require("pl.tablex").keys(body), function(x) return x:match( "%[%]$") end) then
        headers["Content-Type"] = "application/x-www-form-urlencoded"
      end

      local res = assert(client:send{
        method = "PUT",
        path = path,
        body = body or {},
        headers = headers
      })

      return cjson.decode(assert.res_status(expected_status or 200, res))
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

    before_each(function()
      helpers.get_db_utils(strategy)

      assert(helpers.start_kong{
        database = strategy,
        portal_auth = "basic-auth",  -- useful only for admin test
        mock_smtp = true,
        plugins = "oauth2",
      })
      client = assert(helpers.admin_client())
    end)


    after_each(function()
      helpers.stop_kong()
    end)

    it("returns 404 if we call from another workspace", function()
      post("/workspaces", {name = "ws1"})
      get("/ws1/workspaces/default/meta", nil, 404)
    end)

    it("increments with POST", function()
      post("/services", { name = "s1", host="s1.test"})
      local res = get("/default/workspaces/default/meta")
      assert.equals(1, res.counts.services)
    end)

    it("decrements with DELETE", function()
      local s = post("/services", { name = "s1", host="s1.test"})
      delete("/services/" .. s.id)
      local res = get("/default/workspaces/default/meta")
      assert.equals(0, res.counts.services)
    end)

    it("decrements with DELETE by name", function()
      local s = post("/services", { name = "s1", host="s1.test"})
      delete("/services/" .. s.name)
      local res = get("/default/workspaces/default/meta")
      assert.equals(0, res.counts.services)
    end)

    it("obeys PUT upsert", function()
      put("/services/57ec3997-f184-4ac5-b985-56ad88923760", {host="s1.test"})
      local res = get("/default/workspaces/default/meta")
      assert.equals(1, res.counts.services)

      put("/services/57ec3997-f184-4ac5-b985-56ad88923760", {host="s2.test"})
      res = get("/default/workspaces/default/meta")
      assert.equals(1, res.counts.services)

      put("/services/57ec3997-f184-4ac5-b985-56ad88923761", {host="s2.test"})
      res = get("/default/workspaces/default/meta")
      assert.equals(2, res.counts.services)
    end)

    it("does not count oauth2_tokens", function()
      local service = post("/services", {
        name = "oauth2",
        url  = "http://test/"
      })

      post("/consumers", { username = "bob" })

      local credential = post("/consumers/bob/oauth2", {
        name          = "test",
        redirect_uris = { "http://superduper.test/" },
      })

      post("/oauth2_tokens", {
        credential = { id = credential.id },
        service    = { id = service.id },
        expires_in = 30,
      })

      local counts = get("/default/workspaces/default/meta").counts
      assert.is_nil(counts.oauth2_tokens)

      assert.equals(1, counts.consumers)
      assert.equals(1, counts.oauth2_credentials)
      assert.equals(1, counts.services)
    end)


  end)
end
