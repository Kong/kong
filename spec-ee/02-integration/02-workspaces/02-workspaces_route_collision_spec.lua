-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local tablex = require "pl.tablex"


local client


local function it_content_types(title, fn)
  -- Supported content types:
  -- https://docs.konghq.com/1.3.x/admin-api/#supported-content-types
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  local test_multipart = fn("multipart/form-data")

  it(title .. " with application/json", test_json)
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with multipart/form-data", test_multipart)
end


local function any(t, p)
  return #tablex.filter(t, p) > 0
end


local function send_request(method, default_status, path, body, headers, expected_status)
  headers = headers or {}
  if not headers["Content-Type"] then
    headers["Content-Type"] = "application/json"
  end

  if any(tablex.keys(body), function(x) return x:match("%[%]$") end) then
    headers["Content-Type"] = "application/x-www-form-urlencoded"
  end

  local res = assert(client:send {
    method = method,
    path = path,
    body = body or {},
    headers = headers
  })

  return cjson.decode(assert.res_status(expected_status or default_status, res))
end


local function post(path, body, headers, expected_status)
  return send_request("POST", 201, path, body, headers, expected_status)
end
local function patch(path, body, headers, expected_status)
  return send_request("PATCH", 200, path, body, headers, expected_status)
end
local function put(path, body, headers, expected_status)
  return send_request("PUT", 200, path, body, headers, expected_status)
end


for _, strategy in helpers.each_strategy() do

  describe("DB [#" .. strategy .. "] routes are checked for collisions ", function()
    local route, default_service, service_ws2
    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "services",
        "routes",
      })

      assert(helpers.start_kong({
        database = strategy,
      }))

      client = assert(helpers.admin_client())

      post("/workspaces", { name = "ws1" })
      post("/workspaces", { name = "ws2" })
      default_service = post("/ws1/services", {name = "default-service", host = "test-1.test"})
      post("/ws2/services", { name = "default-service", host = "test-2.test" })
      route = post("/ws1/services/default-service/routes", { ['hosts[]'] = "example.org" })
      post("/ws1/services/default-service/routes", { paths = { "/route" } })
      post("/ws1/services/default-service/routes", { hosts = { "example.com" } })
      post("/ws1/services/default-service/routes", { methods = { "GET" } })

      post("/ws1/services", {
        name = "service_ws1",
        url = "http://test.test",
      })

      service_ws2 = post("/ws2/services", {
        name = "service_ws2",
        url = "http://test.test",
      })

      post("/ws1/services/service_ws1/routes", {
        name = "route_ws1",
        paths = { "/test" },
      })

      post("/ws2/services/service_ws2/routes", {
        name = "route_ws2",
        paths = { "/2test" },
      })

      post("/ws1/services/service_ws1/routes", {
        headers = {
          locations = {
            "USA",
          },
        },
      })

      post("/ws1/services/service_ws1/routes", {
        paths = { "/foo" },
      })

      post("/ws1/services/service_ws1/routes", {
        snis = { "example.com" },
      })

      -- add service in ws1
      post("/ws1/services", {
        name = "mock.service",
        url = "http://httpbin.org",
      })
      -- add service in ws2
      post("/ws2/services", {
        name = "mock.service",
        url = "http://httpbin.org",
      })
      -- add route `mock.route` in ws1
      post("/ws1/services/mock.service/routes", {
        name = "mock.route",
        ["paths[]"] = "/route_ws",
        ["methods[]"] = "GET",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      client:close()
    end)

    it("returns 400 on invalid requests", function()
      local res = assert(client:send {
        method = "POST",
        path = "/ws2/services/default-service/routes",
        body = '{"protocols":["http"],"methods":["GET"],"hosts":[],"paths":[null],"strip_path":true,"preserve_host":false,"service":{"id":"'.. default_service.id .. '"}}',
        headers = { ["Content-Type"] = "application/json" }
      })
      return cjson.decode(assert.res_status(400, res))
    end)

    it("collides when 1 route swallows traffic from  different ws", function()
      post("/ws2/services/default-service/routes",
        { ['hosts[]'] = "example.org" }, nil, 409)
      post("/ws2/services/nonexistent/routes",
        { ['hosts[]'] = "example.org" }, nil, 404)
    end)

    -- Collides when a route swallows traffic from a different ws.
    it_content_types("paths attribute: same prefix", function(content_type)
      return function()
        local headers = { ["Content-Type"] = content_type }

        post("/ws2/services/default-service/routes", {
          paths = "/route2",
        }, headers, 409)
      end
    end)

    -- Collides when a route swallows traffic from a different ws.
    it_content_types("paths attribute: different prefix", function(content_type)
      return function()
        local headers = { ["Content-Type"] = content_type }

        if content_type == "application/json" then
          post("/ws2/services/default-service/routes", {
            paths = { "/2route" },
          }, headers, 201)
        else
          post("/ws2/services/default-service/routes", {
            paths = "/2route",
          }, headers, 201)
        end
      end
    end)

    -- Collides when a route swallows traffic from a different ws.
    it_content_types("paths attribute: identical", function(content_type)
      return function()
        local headers = { ["Content-Type"] = content_type }

        post("/ws2/services/default-service/routes", {
          paths = "/route",
        }, headers, 409)
      end
    end)

    -- Collides when a route swallows traffic from a different ws.
    it_content_types("when the hosts attribute is set", function(content_type)
      local headers = { ["Content-Type"] = content_type }

      return function()
        post("/ws2/services/default-service/routes", {
          hosts = "example.com",
        }, headers, 409)
      end
    end)

    -- Collides when a route swallows traffic from a different ws.
    it_content_types("when the methods attribute is set", function(content_type)
      return function()
        local headers = { ["Content-Type"] = content_type }

        post("/ws2/services/default-service/routes", {
          methods = "GET",
        }, headers, 409)
      end
    end)

    it_content_types("headers", function(content_type)
      return function()
        if content_type == "multipart/form-data" then
          -- the client doesn't play well with this
          return
        end

        local headers = { ["Content-Type"] = content_type }

        post("/ws2/services/service_ws2/routes", {
          headers = {
            locations = {
              "USA",
            },
          },
        }, headers, 409)

        post("/ws2/services/service_ws2/routes", {
          headers = {
            locations = {
              "USA",
              "BRA"
            },
          },
        }, headers, 409)

        post("/ws2/services/service_ws2/routes", {
          headers = {
            locations = {
              "Brazil",
            },
          },
        }, headers, 201)

        if content_type == "application/json" then
          post("/ws2/services/service_ws2/routes", {
            paths = { "/foo" },
            headers = {
              name = {
                "value",
              },
            },
          }, headers, 409)
        else
          post("/ws2/services/service_ws2/routes", {
            paths = "/foo",
            headers = {
              name = {
                "value",
              },
            },
          }, headers, 409)
        end
      end
    end)

    it_content_types("snis", function(content_type)
      return function()
        if content_type == "multipart/form-data" then
          -- the client doesn't play well with this
          return
        end

        local headers = { ["Content-Type"] = content_type }

        post("/ws2/services/service_ws2/routes", {
          snis = "example.com",
        }, headers, 409)

        post("/ws2/services/service_ws2/routes", {
          paths = "/foo",
          snis = "foo.com"
        }, headers, 409)
      end
    end)

    it("doesn't collide if we are in the same ws", function()
      post("/ws1/services/default-service/routes",
        { ["hosts[]"] = "example.org" })
    end)

    it("doesn't collide for distinct routes", function()
      post("/ws2/services/default-service/routes",
        { ["hosts[]"] = "new-host.org" })
    end)

    it("can be updated with patch", function()
      patch("/ws1/routes/" .. route.id, { ["protocols[]"] = "http" })
    end)

    it("#collides when updating with patch", function()
      local r = post("/ws2/services/default-service/routes",
        { ["hosts[]"] = "bla.org" })
      patch("/ws2/routes/" .. r.id, { ['hosts[]'] = "example.org" }, nil, 409)
    end)

    it("can be added with put", function()
      put("/ws1/routes/" .. route.id, { ['hosts[]'] = "example.org", ["protocols[]"] = "http" })
    end)

    it("#collides when adding with put", function()
      local r = post("/ws2/services/default-service/routes",
        { ["hosts[]"] = "bla.org" })
      put("/ws2/routes/" .. r.id, { ['hosts[]'] = "example.org" }, nil, 409)
    end)

    it("doesn't collide when updating itself", function()
      local r = post("/ws2/services/default-service/routes",
        { ['hosts[]'] = "bla.org" })
      patch("/ws2/routes/" .. r.id, { ['hosts[]'] = "bla.org" }, nil, 200)
    end)

    it_content_types("when PATCHing", function(content_type)
      local function array_for(s)
        if content_type == "application/json" then
          return { s }
        else
          return s
        end
      end
      return function()
        local headers = { ["Content-Type"] = content_type }

        patch("/ws2/routes/route_ws2", {
          paths = array_for("/test"),
        }, headers, 409)

        patch("/ws2/services/" .. service_ws2.id .. "/routes/route_ws2", {
          paths = array_for("/test"),
        }, headers, 409)
      end
    end)

    it_content_types("#collides when updating with patch in different workspaces", function(content_type)
      return function()
        if content_type == "multipart/form-data" then
          return
        end
        -- add route `mock.route` in ws2
        post("/ws2/services/mock.service/routes", {
          ["paths[]"] = "/route_ws",
        }, nil, 409)

        post("/ws2/services/mock.service/routes", {
          ["methods[]"] = "GET",
        }, nil, 409)

        -- add route  in ws2
        local route_ws2 = post("/ws2/services/mock.service/routes", {
          ["methods[]"] = "POST",
        }, nil, 201)

        -- update route via id in ws2
        patch("/ws2/routes/" .. route_ws2.id, { methods = { "GET" } }, nil, 409)
        patch("/ws2/routes/" .. route_ws2.id, { methods = { "GET" } }, nil, 409)
        patch("/ws2/routes/" .. route_ws2.id, { paths = { "/route_ws" } }, nil, 409)
      end
    end)
    
    it("handles same parameter in url and params gracefully", function()
      put("/ws1/routes/new_route", { routes = { name = "route_name" } }, nil, 400)
    end)
    
  end)

  describe("DB [" .. strategy .. "] with route_validation_strategy = off", function()
    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "services",
        "routes",
      })

      assert(helpers.start_kong({
        database   = strategy,
        route_validation_strategy = 'off',
      }))

      client = assert(helpers.admin_client())

      post("/workspaces", {name = "ws1"})
      post("/workspaces", {name = "ws2"})
      post("/ws1/services", {name = "default-service", host = "test-1.test"})
      post("/ws2/services", {name = "default-service", host = "test-2.test"})
      post("/ws1/services/default-service/routes", {["hosts[]"] = "example.org"})
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      client:close()
    end)

    it("collision checks do not happen", function()
      post("/ws2/services/default-service/routes", { ["hosts[]"] = "example.org" })
    end)

  end)

end
