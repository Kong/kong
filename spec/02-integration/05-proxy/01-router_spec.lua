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

  describe("percent-encoded URIs", function()

    setup(function()
      insert_apis {
        {
          name = "api-1",
          upstream_url = "http://httpbin.org",
          uris = "/endel%C3%B8st",
        },
        {
          name = "api-2",
          upstream_url = "http://httpbin.org",
          uris = "/foo/../bar",
        },
      }

      assert(helpers.start_kong())
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    it("routes when [uris] is percent-encoded", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/endel%C3%B8st",
        headers = { ["kong-debug"] = 1 },
      })

      assert.res_status(200, res)
      assert.equal("api-1", res.headers["kong-api-name"])
    end)

    it("matches against non-normalized URI", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/foo/../bar",
        headers = { ["kong-debug"] = 1 },
      })

      assert.res_status(200, res)
      assert.equal("api-2", res.headers["kong-api-name"])
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
          upstream_url = "http://localhost:9999/headers-inspect",
          hosts = "preserved.com",
        },
        {
          name = "api-2",
          preserve_host = false,
          upstream_url = "http://localhost:9999/headers-inspect",
          hosts = "discarded.com",
        },
        {
          name = "api-3",
          strip_uri = false,
          preserve_host = true,
          upstream_url = "http://localhost:9999",
          uris = "/headers-inspect",
        }
      }

      assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    describe(" = false (default)", function()
      it("uses hostname from upstream_url", function()
        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = { ["Host"] = "discarded.com" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.matches("localhost", json.host, nil, true) -- not testing :port
      end)

      it("uses port value from upstream_url if not default", function()
        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = { ["Host"] = "discarded.com" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.matches(":9999", json.host, nil, true) -- not testing hostname
      end)
    end)

    describe(" = true", function()
      it("forwards request Host", function()
        local res = assert(client:send {
          method = "GET",
          path = "/",
          headers = { ["Host"] = "preserved.com" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("preserved.com", json.host)
      end)

      it("forwards request Host:Port even if port is default", function()
        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = { ["Host"] = "preserved.com:80" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("preserved.com:80", json.host)
      end)

      it("forwards request Host:Port if port isn't default", function()
        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = { ["Host"] = "preserved.com:123" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("preserved.com:123", json.host)
      end)

      it("forwards request Host even if not matched by [hosts]", function()
        local res = assert(client:send {
          method = "GET",
          path = "/headers-inspect",
          headers = { ["Host"] = "preserved.com" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("preserved.com", json.host)
      end)
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

  describe("trailing slash", function()
    local checks = {
      -- upstream url    uris            request path    expected path           strip uri
      {  "/",            "/",            "/",            "/",                    nil       },
      {  "/",            "/",            "/foo/bar",     "/foo/bar",             nil       },
      {  "/",            "/",            "/foo/bar/",    "/foo/bar/",            nil       },
      {  "/",            "/foo/bar",     "/foo/bar",     "/",                    nil       },
      {  "/",            "/foo/bar/",    "/foo/bar/",    "/",                    nil       },
      {  "/foo/bar",     "/",            "/",            "/foo/bar",             nil       },
      {  "/foo/bar",     "/",            "/foo/bar",     "/foo/bar/foo/bar",     nil       },
      {  "/foo/bar",     "/",            "/foo/bar/",    "/foo/bar/foo/bar/",    nil       },
      {  "/foo/bar",     "/foo/bar",     "/foo/bar",     "/foo/bar",             nil       },
      {  "/foo/bar",     "/foo/bar/",    "/foo/bar/",    "/foo/bar/",            nil       },
      {  "/foo/bar/",    "/",            "/",            "/foo/bar/",            nil       },
      {  "/foo/bar/",    "/",            "/foo/bar",     "/foo/bar/foo/bar",     nil       },
      {  "/foo/bar/",    "/",            "/foo/bar/",    "/foo/bar/foo/bar/",    nil       },
      {  "/foo/bar/",    "/foo/bar",     "/foo/bar",     "/foo/bar",             nil       },
      {  "/foo/bar/",    "/foo/bar/",    "/foo/bar/",    "/foo/bar/",            nil       },
      {  "/",            "/",            "/",            "/",                    true      },
      {  "/",            "/",            "/foo/bar",     "/foo/bar",             true      },
      {  "/",            "/",            "/foo/bar/",    "/foo/bar/",            true      },
      {  "/",            "/foo/bar",     "/foo/bar",     "/",                    true      },
      {  "/",            "/foo/bar/",    "/foo/bar/",    "/",                    true      },
      {  "/foo/bar",     "/",            "/",            "/foo/bar",             true      },
      {  "/foo/bar",     "/",            "/foo/bar",     "/foo/bar/foo/bar",     true      },
      {  "/foo/bar",     "/",            "/foo/bar/",    "/foo/bar/foo/bar/",    true      },
      {  "/foo/bar",     "/foo/bar",     "/foo/bar",     "/foo/bar",             true      },
      {  "/foo/bar",     "/foo/bar/",    "/foo/bar/",    "/foo/bar/",            true      },
      {  "/foo/bar/",    "/",            "/",            "/foo/bar/",            true      },
      {  "/foo/bar/",    "/",            "/foo/bar",     "/foo/bar/foo/bar",     true      },
      {  "/foo/bar/",    "/",            "/foo/bar/",    "/foo/bar/foo/bar/",    true      },
      {  "/foo/bar/",    "/foo/bar",     "/foo/bar",     "/foo/bar",             true      },
      {  "/foo/bar/",    "/foo/bar/",    "/foo/bar/",    "/foo/bar/",            true      },
      {  "/",            "/",            "/",            "/",                    false     },
      {  "/",            "/",            "/foo/bar",     "/foo/bar",             false     },
      {  "/",            "/",            "/foo/bar/",    "/foo/bar/",            false     },
      {  "/",            "/foo/bar",     "/foo/bar",     "/foo/bar",             false     },
      {  "/",            "/foo/bar/",    "/foo/bar/",    "/foo/bar/",            false     },
      {  "/foo/bar",     "/",            "/",            "/foo/bar",             false     },
      {  "/foo/bar",     "/",            "/foo/bar",     "/foo/bar/foo/bar",     false     },
      {  "/foo/bar",     "/",            "/foo/bar/",    "/foo/bar/foo/bar/",    false     },
      {  "/foo/bar",     "/foo/bar",     "/foo/bar",     "/foo/bar/foo/bar",     false     },
      {  "/foo/bar",     "/foo/bar/",    "/foo/bar/",    "/foo/bar/foo/bar/",    false     },
      {  "/foo/bar/",    "/",            "/",            "/foo/bar/",            false     },
      {  "/foo/bar/",    "/",            "/foo/bar",     "/foo/bar/foo/bar",     false     },
      {  "/foo/bar/",    "/",            "/foo/bar/",    "/foo/bar/foo/bar/",    false     },
      {  "/foo/bar/",    "/foo/bar",     "/foo/bar",     "/foo/bar/foo/bar",     false     },
      {  "/foo/bar/",    "/foo/bar/",    "/foo/bar/",    "/foo/bar/foo/bar/",    false     },
    }

    setup(function()
      helpers.dao:truncate_tables()

      for i, args in ipairs(checks) do
        assert(helpers.dao.apis:insert {
            name         = "localbin-" .. i,
            strip_uri    = args[5],
            upstream_url = "http://localhost:9999" .. args[1],
            uris         = {
              args[2],
            },
            hosts        = {
              "localbin-" .. i .. ".com",
            },
        })
      end

      assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    local function check(i, request_uri, expected_uri)
      return function()
        local res = assert(client:send {
          method  = "GET",
          path    = request_uri,
          headers = {
            ["Host"] = "localbin-" .. i .. ".com",
          }
        })

        local json = assert.res_status(200, res)
        local data = cjson.decode(json)

        assert.equal(expected_uri, data.vars.request_uri)
      end
    end

    for i, args in ipairs(checks) do

      local config = "(strip_uri = n/a)"

      if args[5] == true then
        config = "(strip_uri = on) "

      elseif args[5] == false then
        config = "(strip_uri = off)"
      end

      it(config .. " is not appended to upstream url " .. args[1] ..
                   " (with uri "                       .. args[2] .. ")" ..
                   " when requesting "                 .. args[3],
        check(i, args[3], args[4]))
    end
  end)
end)
