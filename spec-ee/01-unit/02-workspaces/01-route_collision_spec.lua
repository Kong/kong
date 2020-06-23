local route_collision = require "kong.enterprise_edition.workspaces.route_collision"

describe("route_collision", function()
  local DB = require "kong.db"
  local kong_config = {
    database = "postgres"
  }
  _G.kong = {
    db = DB.new(kong_config)
  }

  describe("adding a route", function()
    local routes
    setup(function()
      routes = {
        {
          headers = {
            host = { "myapi1" }
          },
          hosts = { "myapi1" },
          paths = {"/yeah"},
          methods = { "POST", "PUT", "GET" },
          name = "foo2",
          upstream_url = "https://requestb.in/w2r6y3w2",
          ws_id = "default",
        }, {
          headers = {
            host = { "myapi1" }
          },
          hosts = { "myapi1" },
          name = "blabla",
          paths = {"/"},
          upstream_url = "https://requestb.in/w2r6y3w2",
          ws_id = "foo",
        }, {
          name = "api-1",
          methods = { "POST", "PUT", "GET" },
          paths = { "/my-api" },
          ws_id = "ws1",
        }, {
          name = "api-2",
          methods = { "POST", "PUT", "GET" },
          paths = { "/my-api2" },
          ws_id = "ws2",
        }, {
          headers = {
            host = { "*" }
          },
          hosts = { "*" },
          name = "api-3",
          methods = { "POST", "PUT", "GET" },
          paths = { "/my-api3" },
          ws_id = "ws3",
        }, {
          hosts = { "host4" },
          name = "api-4",
          methods = { "POST", "PUT", "GET" },
          paths = { "/api4" },
          ws_id = "ws4",
        }, {
          name = "api-5",
          hosts = nil,
          methods = { "POST", "PUT", "GET" },
          paths = { "/my-api5" },
          ws_id = "ws2",
        }
      }

      local s = {{id = "dc0a9bdd-b1e0-4c6d-9218-6e9f1e0a9e6b"}}
      for i, r in ipairs(routes) do
        routes[i] = {route = r, service = s}
      end

    end)

    it("selects routes correctly", function()
      local Router = require "kong.router"

      local r = assert(Router.new(routes))

      assert.equal("api-2", route_collision._match_route(r, "GET", "/my-api2", "h1").route.name)
    end)

    it("adds root route to an empty router", function()
      local Router = require "kong.router"
      local r = Router.new({})
      assert.truthy(route_collision._validate_route_for_ws(r, "GET", "/", "bla"))
    end)

    it("adds route in the same ws", function()
      local Router = require "kong.router"
      local r = Router.new(routes)
      assert.truthy(route_collision._validate_route_for_ws(r, "GET", "/api4", "host4", nil, nil, {id = "ws4"}))
    end)

    it("ADD route in different ws, no host in existing one", function()
      local Router = require "kong.router"
      local r = Router.new(routes)
      assert.falsy(route_collision._validate_route_for_ws(r, "GET", "/my-api2", "hi", nil, nil, {id = "ws3"}))
    end)

    it("NOT add route in different ws, with same wildcard host", function()
      local Router = require "kong.router"
      local r = Router.new(routes)
      assert.equal("api-3", route_collision._match_route(r, "GET", "/my-api3",
                                                   "h*").route.name)
      assert.falsy(
        route_collision._validate_route_for_ws(r, "GET", "/my-api3", "*", nil, nil, {id = "ws4"}))
    end)

    it("ADD route in different ws, with different wildcard host", function()
      local Router = require "kong.router"
      local r = Router.new(routes)
      assert.equal("api-3", route_collision._match_route(r, "GET", "/my-api3", "h*").route.name)
      assert.truthy(route_collision._validate_route_for_ws(r, "GET", "/my-api3", "*.foo.com", nil, nil, {id = "ws4"}))
    end)

    it("NOT add route in different ws, with full host in the conflicting route", function()
      local Router = require "kong.router"
      local r = Router.new(routes)
      assert.equal("api-4", route_collision._match_route(r, "GET", "/api4", "host4").route.name)
      assert.falsy(route_collision._validate_route_for_ws(r, "GET", "/api4", "host4", nil, nil, {id = "different"}))
    end)

  end)
  describe("permutations", function()
    it("works for single array", function()
      local iter = route_collision._permutations({1,2})
      assert.are.same({1}, iter())
      assert.are.same({2}, iter())
      assert.falsy(iter())
    end)

    it("works for 2 arrays", function()
      local iter = route_collision._permutations({1,2}, {3,4})
      assert.are.same({1,3}, iter())
      assert.are.same({1,4}, iter())
      assert.are.same({2,3}, iter())
      assert.are.same({2,4}, iter())
      assert.falsy(iter())
    end)

    it("works for single-pos-array", function()
      local iter = route_collision._permutations({1}, {3,4})
      assert.are.same({1,3}, iter())
      assert.are.same({1,4}, iter())
      assert.falsy(iter())
      iter = route_collision._permutations({1,2}, {4})
      assert.are.same({1,4}, iter())
      assert.are.same({2,4}, iter())
      assert.falsy(iter())
    end)

    it("works for n arrays", function()
      local iter = route_collision._permutations({1}, {2}, {3,4})
      assert.are.same({1, 2, 3}, iter())
      assert.are.same({1, 2, 4}, iter())
      assert.falsy(iter())
    end)

    it("works for n arrays", function()
      local iter = route_collision._permutations({2}, {3,4})
      assert.are.same({2,3}, iter())
      assert.are.same({2,4}, iter())
      assert.falsy(iter())
    end)

    it("iterates ok with set of only an empty string", function()
      local iter = route_collision._permutations({""}, {3,4})
      assert.are.same({"", 3}, iter())
      assert.are.same({"", 4}, iter())
      assert.falsy(iter())
    end)

    it("works as a loop iterator", function()
      local res = {}
      for i in route_collision._permutations({1}, {2,3}) do
        res[#res+1] = i
      end
      assert.are.same({{1,2}, {1,3}}, res)
      end)

  end)
end)
