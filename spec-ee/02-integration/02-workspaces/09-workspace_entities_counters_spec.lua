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

    it("returns 404 if we call from another workspace", function()
      post("/workspaces", {name = "ws1"})
      get("/ws1/workspaces/default/meta", nil, 404)
    end)
  end)
end
