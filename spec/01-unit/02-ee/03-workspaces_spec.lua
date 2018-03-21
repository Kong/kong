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
      assert.is_true(workspaces.register_workspaceable_relation("rel1", {"id1"}))
      assert.is_true(workspaces.register_workspaceable_relation("rel2", {"id2"}))
      assert.equal(workspaceable_relations.rel1, "id1")
      assert.equal(workspaceable_relations.rel2, "id2")
    end)
    it("iterates", function()
      local items = {rel1 = "id1", rel2 = "id2"}
      for k, v in pairs(workspaceable_relations) do
        if items[k] then
          assert.equals(v, items[k])
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
    local Router = require "kong.core.router"
    local method = "GET"
    local uri = "/"
    local host = "myapi1"

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
        workspace = "default"
      }, {
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
        workspace = "foo"
       }, {
        name = "api-1",
        methods = { "POST", "PUT", "GET" },
        uris = { "/my-api" },
        workspace = "ws1" ,
       }, {
        name = "api-2",
        methods = { "POST", "PUT", "GET" },
        uris = { "/my-api2" },
        workspace = {"ws2"} ,
      }
    }
    local  r = Router.new(apis)
    local matched_route = r.select("GET", "/","")
    assert.falsy(matched_route)

    matched_route = r.select("GET", "/","myapi1")
    assert.truthy(matched_route)

    matched_route = r.select("GET", "/my-api","")
    assert.truthy(matched_route)

    matched_route = workspaces.match_route(r, "GET", "/my-api", "")
    assert.truthy(matched_route)
    assert.truthy(workspaces.api_in_ws(matched_route.api, "ws1"))

    matched_route = workspaces.match_route(r, "GET", "/my-api2", "")
    assert.truthy(matched_route)
    assert.truthy(workspaces.api_in_ws(matched_route.api, "ws2"))
    assert.falsy(workspaces.api_in_ws(matched_route.api, "ws1"))
  end)

  describe("api_in_ws accepts", function()
    local single_api, multiple_api = {}, {}

    setup(function()
      single_api = {
        name = "api-2",
        methods = { "POST", "PUT", "GET" },
        uris = { "/my-api2" },
        workspace = "ws1" ,
      }
      multiple_api = {
        name = "api-2",
        methods = { "POST", "PUT", "GET" },
        uris = { "/my-api2" },
        workspace = {"ws1", "ws2"} ,
      }
    end)

    it("single ws per entity", function()
      assert.truthy(workspaces.api_in_ws(single_api, "ws1"))
      assert.falsy(workspaces.api_in_ws(single_api, "ws2"))
      assert.falsy(workspaces.api_in_ws(single_api, "nope"))
    end)

    it("multiple ws per entity", function()
      assert.truthy(workspaces.api_in_ws(multiple_api, "ws1"))
      assert.truthy(workspaces.api_in_ws(multiple_api, "ws2"))
      assert.falsy(workspaces.api_in_ws(multiple_api, "nope"))
    end)
  end)


end)
