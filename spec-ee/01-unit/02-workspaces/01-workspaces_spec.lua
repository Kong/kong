local workspaces = require "kong.workspaces"

describe("workspaces", function()
  local workspaceable_relations = workspaces.get_workspaceable_relations()
  describe("workspaceable relations", function()
    it("is a table", function()
      assert.is_table(workspaceable_relations)
    end)
    it("is immutable", function()
      local ok, err = pcall(function()
        workspaceable_relations.newfield = 123
      end)
      assert.falsy(ok)
      assert.matches("immutable table", err)
    end)
    it("can be added", function()
      local unique_keys = {
        field1 = {
          schema = {
            fields = {
              id = {
                dao_insert_value = true,
                required = true,
                type = "id"
              },
              field1 = {
                required = true,
                type = "string",
                unique = true
              },
            },
          },
          table = "rel3"
        }
      }
      assert.is_true(workspaces.register_workspaceable_relation("rel1", {"id1"}))
      assert.is_true(workspaces.register_workspaceable_relation("rel2", {"id2"}))
      assert.is_true(workspaces.register_workspaceable_relation("rel3", {"id3"}, unique_keys))
      assert.equal(workspaceable_relations.rel1.primary_key, "id1")
      assert.equal(workspaceable_relations.rel2.primary_key, "id2")
      assert.equal(workspaceable_relations.rel3.primary_key, "id3")
      assert.is_same(workspaceable_relations.rel3.unique_keys, unique_keys)
    end)
    it("iterates", function()
      local items = {
        rel1 = { primary_key = "id1", primary_keys = {id1 = true} },
        rel2 = { primary_key = "id2", primary_keys = {id2 = true} },
        rel3 = {
          primary_key = "id3",
          primary_keys = {id3 = true},
          unique_keys = {
            field1 = {
              schema = {
                fields = {
                  id = {
                    dao_insert_value = true,
                    required = true,
                    type = "id"
                  },
                  field1 = {
                    required = true,
                    type = "string",
                    unique = true
                  },
                },
              },
              table = "rel3"
            }
          }
        },
      }
      for k, v in pairs(workspaceable_relations) do
        if items[k] then
          assert.is_same(v, items[k])
        end
      end
    end)
    it("has a protected metatable", function()
      local ok, val = pcall(getmetatable, workspaceable_relations)
      assert.is_true(ok)
      assert.is_false(val)
    end)
  end)

  it("is able to detect a matching [host, uri, method ] in the router", function()
    local Router = require "kong.core.api_router"

    local apis = {
      {
        created_at = 1521209668855,
        headers = {
          host = { "myapi1" }
        },
        hosts = { "myapi1" },
        http_if_terminated = false,
        https_only = false,
        id = "cd3205b8-5e52-4951-829d-fee3e38949b2",
        name = "foo2",
        preserve_host = false,
        retries = 5,
        strip_uri = true,
        upstream_connect_timeout = 60000,
        upstream_read_timeout = 60000,
        upstream_send_timeout = 60000,
        upstream_url = "https://requestb.in/w2r6y3w2",
        workspace = {{ id = "default"}}
      },
      {
        created_at = 1521494974461,
        headers = {
          host = { "myapi1" }
        },
        hosts = {"myapi1"},
        http_if_terminated = false,
        https_only = false,
        id = "6b4d66b6-f615-44fe-bfec-116a6a37bdf1",
        name = "blabla",
        preserve_host = false,
        retries = 5,
        strip_uri = true,
        upstream_connect_timeout = 60000,
        upstream_read_timeout = 60000,
        upstream_send_timeout = 60000,
        upstream_url = "https://requestb.in/w2r6y3w2",
        workspaces = {{ id = "foo"}}
      },
      {
        name = "api-1",
        methods = { "POST", "PUT", "GET" },
        uris = { "/my-api" },
        workspaces = {{ id = "ws1"}} ,
      },
      {
        name = "api-2",
        methods = { "POST", "PUT", "GET" },
        uris = { "/my-api2" },
        workspaces = {{id = "ws2"}} ,
      }
    }
    local r = Router.new(apis)
    local matched_route = r.select("GET", "/","")
    local ws1 = {id = "ws1"}
    local ws2 = {id = "ws2"}
    assert.falsy(matched_route)

    matched_route = r.select("GET", "/","myapi1")
    assert.truthy(matched_route)

    matched_route = r.select("GET", "/my-api","")
    assert.truthy(matched_route)

    matched_route = workspaces.match_route(r, "GET", "/my-api", "")
    assert.truthy(matched_route)
    assert.truthy(workspaces.is_api_in_ws(matched_route.api, ws1))

    matched_route = workspaces.match_route(r, "GET", "/my-api2", "")
    assert.truthy(matched_route)
    assert.truthy(workspaces.is_api_in_ws(matched_route.api, ws2))
    assert.falsy(workspaces.is_api_in_ws(matched_route.api, ws1))
  end)

  describe("is_api_in_ws accepts", function()
    local single_api, multiple_api
    local ws1 = {id = "ws1"}
    local ws2 = {id = "ws2"}

    setup(function()
      single_api = {
        name = "api-2",
        methods = { "POST", "PUT", "GET" },
        uris = { "/my-api2" },
        workspaces = {{id = "ws1"}},
      }
      multiple_api = {
        name = "api-2",
        methods = { "POST", "PUT", "GET" },
        uris = { "/my-api2" },
        workspaces = {{ id = "ws1" }, { id = "ws2"}},
      }
    end)

    it("single ws per entity", function()
      assert.truthy(workspaces.is_api_in_ws(single_api, ws1))
      assert.falsy(workspaces.is_api_in_ws(single_api, ws2))
      assert.falsy(workspaces.is_api_in_ws(single_api, {id = "nope"}))
    end)

    it("multiple ws per entity", function()
      assert.truthy(workspaces.is_api_in_ws(multiple_api, ws1))
      assert.truthy(workspaces.is_api_in_ws(multiple_api, ws2))
      assert.falsy(workspaces.is_api_in_ws(multiple_api, {name = "nope"}))
    end)
  end)

  describe("adding a route", function()
      local apis = {
      {
        headers = {
          host = { "myapi1" }
        },
        hosts = { "myapi1" },
        uris = {"/yeah"},
        methods = { "POST", "PUT", "GET" },
        name = "foo2",
        upstream_url = "https://requestb.in/w2r6y3w2",
        workspaces = {{ id = "default"}}
      }, {
        headers = {
          host = { "myapi1" }
        },
        hosts = { "myapi1" },
        name = "blabla",
        upstream_url = "https://requestb.in/w2r6y3w2",
        workspaces = {{ id = "foo"}}
       }, {
        name = "api-1",
        methods = { "POST", "PUT", "GET" },
        uris = { "/my-api" },
        workspaces = {{ id = "ws1"}} ,
       }, {
        name = "api-2",
        methods = { "POST", "PUT", "GET" },
        uris = { "/my-api2" },
        workspaces = {{ id = "ws2" }} ,
      }, {
        headers = {
          host = { "*" }
        },
        hosts = { "*" },
        name = "api-3",
        methods = { "POST", "PUT", "GET" },
        uris = { "/my-api3" },
        workspaces = {{ id = "ws3" }} ,
      }, {
        hosts = { "host4" },
        name = "api-4",
        methods = { "POST", "PUT", "GET" },
        uris = { "/api4" },
        workspaces = {{ id = "ws4" }} ,
      }, {
        name = "api-5",
        hosts = ngx.null,
        methods = { "POST", "PUT", "GET" },
        uris = { "/my-api5" },
        workspaces = {{ id = "ws2" }} ,
      }
    }

    it("selects routes correctly", function()
      local Router = require "kong.core.api_router"
      local r = Router.new(apis)
      assert.equal("api-2", workspaces.match_route(r, "GET", "/my-api2", "h1").api.name)
    end)

    it("adds root route to an empty router", function()
      local Router = require "kong.core.api_router"
      local r = Router.new({})
      assert.truthy(workspaces.validate_route_for_ws(r, "GET", "/", "bla"))
    end)

    it("adds route in the same ws", function()
      local Router = require "kong.core.api_router"
      local r = Router.new(apis)
      assert.truthy(workspaces.validate_route_for_ws(r, "GET", "/api4", "host4", {id = "ws4"}))
    end)

    it("ADD route in different ws, no host in existing one", function()
      local Router = require "kong.core.api_router"
      local r = Router.new(apis)
      assert.falsy(workspaces.validate_route_for_ws(r, "GET", "/my-api2", "hi", {id = "ws3"}))
    end)

    it("NOT add route in different ws, with same wildcard host", function()
      local Router = require "kong.core.api_router"
      local r = Router.new(apis)
      assert.equal("api-3", workspaces.match_route(r, "GET", "/my-api3",
                                                   "h*").api.name)
      assert.falsy(
        workspaces.validate_route_for_ws(r, "GET", "/my-api3", "*", {id = "ws4"}))
    end)

    it("ADD route in different ws, with different wildcard host", function()
      local Router = require "kong.core.api_router"
      local r = Router.new(apis)
      assert.equal("api-3", workspaces.match_route(r, "GET", "/my-api3", "h*").api.name)
      assert.truthy(workspaces.validate_route_for_ws(r, "GET", "/my-api3", "*.foo.com", {id = "ws4"}))
    end)

    it("NOT add route in different ws, with full host in the conflicting route", function()
      local Router = require "kong.core.api_router"
      local r = Router.new(apis)
      assert.equal("api-4", workspaces.match_route(r, "GET", "/api4", "host4").api.name)
      assert.falsy(workspaces.validate_route_for_ws(r, "GET", "/api4", "host4", {id = "different"}))
    end)

  end)
  describe("permutations", function()
    it("works for single array", function()
      local iter = workspaces.permutations({1,2})
      assert.are.same({1}, iter())
      assert.are.same({2}, iter())
      assert.falsy(iter())
    end)

    it("works for 2 arrays", function()
      local iter = workspaces.permutations({1,2}, {3,4})
      assert.are.same({1,3}, iter())
      assert.are.same({1,4}, iter())
      assert.are.same({2,3}, iter())
      assert.are.same({2,4}, iter())
      assert.falsy(iter())
    end)

    it("works for single-pos-array", function()
      local iter = workspaces.permutations({1}, {3,4})
      assert.are.same({1,3}, iter())
      assert.are.same({1,4}, iter())
      assert.falsy(iter())
      iter = workspaces.permutations({1,2}, {4})
      assert.are.same({1,4}, iter())
      assert.are.same({2,4}, iter())
      assert.falsy(iter())
    end)

    it("works for n arrays", function()
      local iter = workspaces.permutations({1}, {2}, {3,4})
      assert.are.same({1, 2, 3}, iter())
      assert.are.same({1, 2, 4}, iter())
      assert.falsy(iter())
    end)

    it("works for n arrays", function()
      local iter = workspaces.permutations({2}, {3,4})
      assert.are.same({2,3}, iter())
      assert.are.same({2,4}, iter())
      assert.falsy(iter())
    end)

    it("iterates ok with set of only an empty string", function()
      local iter = workspaces.permutations({""}, {3,4})
      assert.are.same({"", 3}, iter())
      assert.are.same({"", 4}, iter())
      assert.falsy(iter())
    end)

    it("works as a loop iterator", function()
      local res = {}
      for i in workspaces.permutations({1}, {2,3}) do
        res[#res+1] = i
      end
      assert.are.same({{1,2}, {1,3}}, res)
      end)

  end)
end)
