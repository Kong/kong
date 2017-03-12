local helpers = require "spec.helpers"
local cjson = require "cjson"

local function insert_apis(arr)
  if type(arr) ~= "table" then
    return error("expected arg #1 to be a table", 2)
  end

  helpers.dao:truncate_tables()

  for i = 1, #arr do
    assert(helpers.dao.apis:insert(arr[i]))
  end
end

describe("Router", function()
  local client

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  describe("no APIs match", function()

    setup(function()
      helpers.dao:truncate_tables()
      assert(helpers.start_kong())
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    it("responds 404 if no API matches", function()
      local res = assert(client:send {
        method = "GET",
        headers = {
          host = "inexistent.com"
        }
      })

      local body = assert.response(res).has_status(404)
      local json = cjson.decode(body)
      assert.matches("^kong/", res.headers.server)
      assert.equal("no API found with those values", json.message)
    end)
  end)

  describe("use-cases", function()

    setup(function()
      insert_apis {
        {
          name = "api-1",
          upstream_url = "http://httpbin.org",
          methods = { "GET" },
        },
        {
          name = "api-2",
          upstream_url = "http://httpbin.org",
          methods = { "POST", "PUT" },
          uris = { "/post", "/put" },
          strip_uri = false,
        },
        {
          name = "api-3",
          upstream_url = "http://httpbin.org/status",
          uris = { "/httpbin" },
          strip_uri = true,
        },
        {
          name = "api-4",
          upstream_url = "http://httpbin.org/basic-auth",
          uris = { "/user" },
          strip_uri = false,
        }
      }

      assert(helpers.start_kong())
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    it("restricts an API to its methods if specified", function()
      -- < HTTP/1.1 POST /post
      -- > 200 OK
      local res = assert(client:send {
        method = "POST",
        path = "/post",
        headers = { ["kong-debug"] = 1 },
      })

      assert.response(res).has_status(200)
      assert.equal("api-2", res.headers["kong-api-name"])

      -- < HTTP/1.1 DELETE /post
      -- > 404 NOT FOUND
      res = assert(client:send {
        method = "DELETE",
        path = "/post",
        headers = { ["kong-debug"] = 1 },
      })

      assert.response(res).has_status(404)
      assert.is_nil(res.headers["kong-api-name"])
    end)

    it("routes by method-only if no other match is found", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = { ["kong-debug"] = 1 },
      })

      assert.response(res).has_status(200)
      assert.equal("api-1", res.headers["kong-api-name"])
    end)

    describe("API with a path component in its upstream_url", function()
      it("with strip_uri = true", function()
        local res = assert(client:send {
          method = "GET",
          path = "/httpbin/201",
          headers = { ["kong-debug"] = 1 },
        })

        assert.res_status(201, res)
        assert.equal("api-3", res.headers["kong-api-name"])
      end)
    end)

    it("with strip_uri = false", function()
        local res = assert(client:send {
          method = "GET",
          path = "/user/passwd",
          headers = { ["kong-debug"] = 1 },
        })

        assert.res_status(401, res)
        assert.equal("api-4", res.headers["kong-api-name"])
    end)
  end)

  describe("invalidation", function()
    local admin_client

    setup(function()
      helpers.dao:truncate_tables()
      assert(helpers.start_kong())

      admin_client = helpers.admin_client()
    end)

    teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    it("updates itself when updating APIs from the Admin API", function()
      local res = assert(client:send {
        method = "GET",
        headers = {
          host = "api.com"
        }
      })
      local body = assert.response(res).has_status(404)
      local json = cjson.decode(body)
      assert.matches("^kong/", res.headers.server)
      assert.equal("no API found with those values", json.message)

      local admin_res = assert(admin_client:send {
        method = "POST",
        path = "/apis",
        body = {
          name = "my-api",
          upstream_url = "http://httpbin.org",
          hosts = "api.com",
        },
        headers = { ["Content-Type"] = "application/json" },
      })
      assert.response(admin_res).has_status(201)

      ngx.sleep(1)

      res = assert(client:send {
        method = "GET",
        headers = {
          host = "api.com"
        }
      })
      assert.response(res).has_status(200)

      admin_res = assert(admin_client:send {
        method = "PATCH",
        path = "/apis/my-api",
        body = {
          hosts = "api.com,foo.com",
          uris = "/foo",
          strip_uri = true,
        },
        headers = { ["Content-Type"] = "application/json" },
      })
      assert.response(admin_res).has_status(200)

      ngx.sleep(1)

      res = assert(client:send {
        method = "GET",
        headers = {
          host = "foo.com"
        }
      })
      assert.response(res).has_status(404)

      res = assert(client:send {
        method = "GET",
        path = "/foo",
        headers = {
          host = "foo.com"
        }
      })
      assert.response(res).has_status(200)
    end)
  end)

  describe("preserve_host", function()

    setup(function()
      insert_apis {
        {
          name = "api-1",
          preserve_host = true,
          upstream_url = "http://httpbin.org",
          hosts = "preserved.com",
        },
        {
          name = "api-2",
          preserve_host = false,
          upstream_url = "http://httpbin.org",
          hosts = "discarded.com",
        }
      }

      assert(helpers.start_kong())
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    it("preserves downstream host if enabled", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = { ["Host"] = "preserved.com" },
      })

      assert.res_status(200, res)
      local json = cjson.decode((res:read_body()))
      assert.equal("preserved.com", json.headers.Host)
    end)

    pending("preserves downstream host+port if enabled", function()
      -- pending because httpbin.org seems to not return the exact header
      -- but a parsed one, with the port stripped.
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = { ["Host"] = "preserved.com:80" },
      })

      assert.res_status(200, res)
      local json = cjson.decode((res:read_body()))
      assert.equal("preserved.com:80", json.headers.Host)
    end)

    pending("preserves downstream host+non_default_port if enabled", function()
      -- pending because httpbin.org seems to not return the exact header
      -- but a parsed one, with the port stripped.
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = { ["Host"] = "preserved.com:123" },
      })

      assert.res_status(200, res)
      local json = cjson.decode((res:read_body()))
      assert.equal("preserved.com:123", json.headers.Host)
    end)

    it("discards downstream host if disabled", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = { ["Host"] = "discarded.com" },
      })

      assert.response(res).has.status(200)
      assert.equal("httpbin.org", assert.request(res).has.header("Host"))
    end)
  end)

  describe("edge-cases", function()

    setup(function()
      insert_apis {
        {
          name = "root-uri",
          upstream_url = "http://httpbin.org",
          uris = "/",
        },
        {
          name = "fixture-api",
          upstream_url = "http://httpbin.org",
          uris = "/foobar",
        },
      }

      assert(helpers.start_kong())
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    it("root / [uri] for a catch-all rule", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = { ["kong-debug"] = 1 }
      })

      assert.response(res).has_status(200)
      assert.equal("root-uri", res.headers["kong-api-name"])

      res = assert(client:send {
        method = "GET",
        path = "/foobar/get",
        headers = { ["kong-debug"] = 1 }
      })

      assert.response(res).has_status(200)
      assert.equal("fixture-api", res.headers["kong-api-name"])
    end)
  end)
end)
