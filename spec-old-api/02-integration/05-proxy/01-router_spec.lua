local helpers = require "spec.helpers"
local cjson = require "cjson"

local function insert_apis(arr)
  if type(arr) ~= "table" then
    return error("expected arg #1 to be a table", 2)
  end

  helpers.dao:truncate_table("apis")

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

    lazy_setup(function()
      helpers.dao:truncate_table("apis")
      helpers.db:truncate("routes")
      helpers.db:truncate("services")
      helpers.dao:run_migrations()
      assert(helpers.start_kong())
    end)

    lazy_teardown(function()
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
      assert.equal("no route and no API found with those values", json.message)
    end)
  end)

  describe("use-cases", function()

    lazy_setup(function()
      insert_apis {
        {
          name         = "api-1",
          upstream_url = helpers.mock_upstream_url,
          methods      = { "GET" },
        },
        {
          name         = "api-2",
          upstream_url = helpers.mock_upstream_url,
          methods      = { "POST", "PUT" },
          uris         = { "/post", "/put" },
          strip_uri    = false,
        },
        {
          name         = "api-3",
          upstream_url = helpers.mock_upstream_url .. "/status",
          uris         = { [[/mock_upstream]] },
          strip_uri    = true,
        },
        {
          name         = "api-4",
          upstream_url = helpers.mock_upstream_url .. "/basic-auth",
          uris         = { "/private" },
          strip_uri    = false,
        },
        {
          name         = "api-5",
          upstream_url = helpers.mock_upstream_url .. "/anything",
          uris         = { [[/users/\d+/profile]] },
          strip_uri    = true,
        },
      }

      helpers.dao:run_migrations()
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
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
          method  = "GET",
          path    = "/mock_upstream/201",
          headers = { ["kong-debug"] = 1 },
        })

        assert.res_status(201, res)
        assert.equal("api-3", res.headers["kong-api-name"])
      end)
    end)

    it("with strip_uri = false", function()
        local res = assert(client:send {
          method = "GET",
          path = "/private/passwd",
          headers = { ["kong-debug"] = 1 },
        })

        assert.res_status(401, res)
        assert.equal("api-4", res.headers["kong-api-name"])
    end)

    it("[uri] with a regex", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/users/foo/profile",
        headers = { ["kong-debug"] = 1 },
      })

      assert.res_status(404, res)

      res = assert(client:send {
        method  = "GET",
        path    = "/users/123/profile",
        headers = { ["kong-debug"] = 1 },
      })

      assert.res_status(200, res)
      assert.equal("api-5", res.headers["kong-api-name"])
    end)
  end)

  describe("URI regexes order of evaluation", function()
    lazy_setup(function()
      helpers.dao:truncate_table("apis")

      assert(helpers.dao.apis:insert {
        name = "api-1",
        uris = { "/status/(re)" },
        upstream_url = helpers.mock_upstream_url .. "/status/200",
      })

      ngx.sleep(0.001)

      assert(helpers.dao.apis:insert {
        name = "api-2",
        uris = { "/status/(r)" },
        upstream_url = helpers.mock_upstream_url .. "/status/200",
      })

      ngx.sleep(0.001)

      assert(helpers.dao.apis:insert {
        name = "api-3",
        uris = { "/status" },
        upstream_url = helpers.mock_upstream_url .. "/status/200",
      })

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("depends on created_at field", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/status/r",
        headers = { ["kong-debug"] = 1 },
      })
      assert.res_status(200, res)
      assert.equal("api-2", res.headers["kong-api-name"])

      res = assert(client:send {
        method = "GET",
        path = "/status/re",
        headers = { ["kong-debug"] = 1 },
      })
      assert.res_status(200, res)
      assert.equal("api-1", res.headers["kong-api-name"])
    end)
  end)

  describe("URI arguments (querystring)", function()

    lazy_setup(function()
      insert_apis {
        {
          name         = "api-1",
          upstream_url = helpers.mock_upstream_url,
          hosts        = { "mock_upstream" },
        },
      }

      helpers.dao:run_migrations()
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("preserves URI arguments", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        query   = {
          foo   = "bar",
          hello = "world",
        },
        headers = {
          ["Host"] = "mock_upstream",
        },
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("bar", json.uri_args.foo)
      assert.equal("world", json.uri_args.hello)
    end)

    it("does proxy an empty querystring if URI does not contain arguments", function()
      local res = assert(client:send {
        method = "GET",
        path   = "/request?",
        headers = {
          ["Host"] = "mock_upstream",
        },
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.matches("/request%?$", json.vars.request_uri)
    end)

    it("does proxy a querystring with an empty value", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get?hello",
        headers = {
          ["Host"] = "mock_upstream",
        },
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.matches("/get%?hello$", json.url)
    end)
  end)

  describe("percent-encoded URIs", function()

    lazy_setup(function()
      insert_apis {
        {
          name         = "api-1",
          upstream_url = helpers.mock_upstream_url,
          uris         = "/endel%C3%B8st",
        },
        {
          name         = "api-2",
          upstream_url = helpers.mock_upstream_url,
          uris         = "/foo/../bar",
        },
      }

      helpers.dao:run_migrations()
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
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

  describe("strip_uri", function()

    lazy_setup(function()
      insert_apis {
        {
          name         = "api-strip-uri",
          upstream_url = helpers.mock_upstream_url,
          uris         = { "/x/y/z", "/z/y/x" },
          strip_uri    = true,
        },
      }

      helpers.dao:run_migrations()
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("= true", function()
      it("strips subsequent calls to an API with different [uris]", function()
        local res_uri_1 = assert(client:send {
          method = "GET",
          path   = "/x/y/z/get",
        })

        local body = assert.res_status(200, res_uri_1)
        local json = cjson.decode(body)
        assert.matches("/get", json.url, nil, true)
        assert.not_matches("/x/y/z/get", json.url, nil, true)

        local res_uri_2 = assert(client:send {
          method = "GET",
          path   = "/z/y/x/get",
        })

        body = assert.res_status(200, res_uri_2)
        json = cjson.decode(body)
        assert.matches("/get", json.url, nil, true)
        assert.not_matches("/z/y/x/get", json.url, nil, true)

        local res_2_uri_1 = assert(client:send {
          method = "GET",
          path   = "/x/y/z/get",
        })

        body = assert.res_status(200, res_2_uri_1)
        json = cjson.decode(body)
        assert.matches("/get", json.url, nil, true)
        assert.not_matches("/x/y/z/get", json.url, nil, true)

        local res_2_uri_2 = assert(client:send {
          method = "GET",
          path   = "/x/y/z/get",
        })

        body = assert.res_status(200, res_2_uri_2)
        json = cjson.decode(body)
        assert.matches("/get", json.url, nil, true)
        assert.not_matches("/x/y/z/get", json.url, nil, true)
      end)
    end)
  end)

  describe("preserve_host", function()

    lazy_setup(function()
      insert_apis {
        {
          name          = "api-1",
          preserve_host = true,
          upstream_url  = helpers.mock_upstream_url .. "/request",
          hosts         = "preserved.com",
        },
        {
          name          = "api-2",
          preserve_host = false,
          upstream_url  = helpers.mock_upstream_url .. "/request",
          hosts         = "discarded.com",
        },
        {
          name          = "api-3",
          strip_uri     = false,
          preserve_host = true,
          upstream_url  = helpers.mock_upstream_url,
          uris          = "/request",
        }
      }

      helpers.dao:run_migrations()
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("x = false (default)", function()
      it("uses hostname from upstream_url", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/get",
          headers = { ["Host"] = "discarded.com" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.matches(helpers.mock_upstream_host,
                       json.headers.host, nil, true) -- not testing :port
      end)

      it("uses port value from upstream_url if not default", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/get",
          headers = { ["Host"] = "discarded.com" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.matches(":" .. helpers.mock_upstream_port,
                        json.headers.host, nil, true) -- not testing hostname
      end)
    end)

    describe(" = true", function()
      it("forwards request Host", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = { ["Host"] = "preserved.com" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("preserved.com", json.headers.host)
      end)

      it("forwards request Host:Port even if port is default", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/get",
          headers = { ["Host"] = "preserved.com:80" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("preserved.com:80", json.headers.host)
      end)

      it("forwards request Host:Port if port isn't default", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/get",
          headers = { ["Host"] = "preserved.com:123" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("preserved.com:123", json.headers.host)
      end)

      it("forwards request Host even if not matched by [hosts]", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/get",
          headers = { ["Host"] = "preserved.com" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("preserved.com", json.headers.host)
      end)
    end)
  end)

  describe("edge-cases", function()

    lazy_setup(function()
      insert_apis {
        {
          name         = "root-uri",
          upstream_url = helpers.mock_upstream_url,
          uris         = "/",
        },
        {
          name         = "fixture-api",
          upstream_url = helpers.mock_upstream_url,
          uris         = "/foobar",
        },
      }

      helpers.dao:run_migrations()
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
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

  describe("[uris] + [methods]", function()

    lazy_setup(function()
      insert_apis {
        {
          name = "root-api",
          methods = { "GET" },
          uris = "/root",
          upstream_url = helpers.mock_upstream_url,
        },
        {
          name = "fixture-api",
          methods = { "GET" },
          uris = "/root/fixture",
          upstream_url = helpers.mock_upstream_url,
        },
      }

      helpers.dao:run_migrations()
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("prioritizes longer URIs", function()
      local res = assert(client:send {
        method = "GET",
        path = "/root/fixture/get",
        headers = {
          ["kong-debug"] = 1,
        }
      })

      assert.res_status(200, res)
      assert.equal("fixture-api", res.headers["kong-api-name"])
    end)
  end)

  describe("[uris] + [hosts]", function()

    lazy_setup(function()
      insert_apis {
        {
          name         = "root-api",
          hosts        = "api.com",
          uris         = "/root",
          upstream_url = helpers.mock_upstream_url,
        },
        {
          name         = "fixture-api",
          hosts        = "api.com",
          uris         = "/root/fixture",
          upstream_url = helpers.mock_upstream_url,
        },
      }

      helpers.dao:run_migrations()
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("prioritizes longer URIs", function()
      local res = assert(client:send {
        method = "GET",
        path = "/root/fixture/get",
        headers = {
          ["Host"]       = "api.com",
          ["kong-debug"] = 1,
        }
      })

      assert.res_status(200, res)
      assert.equal("fixture-api", res.headers["kong-api-name"])
    end)
  end)

  describe("trailing slash", function()
    local checks = {
      -- upstream url    uris            request path    expected path           strip uri
      {  "/",            "/",            "/",            "/",                    nil       },
      {  "/",            "/",            "/get/bar",     "/get/bar",             nil       },
      {  "/",            "/",            "/get/bar/",    "/get/bar/",            nil       },
      {  "/",            "/get/bar",     "/get/bar",     "/",                    nil       },
      {  "/",            "/get/bar/",    "/get/bar/",    "/",                    nil       },
      {  "/get/bar",     "/",            "/",            "/get/bar",             nil       },
      {  "/get/bar",     "/",            "/get/bar",     "/get/bar/get/bar",     nil       },
      {  "/get/bar",     "/",            "/get/bar/",    "/get/bar/get/bar/",    nil       },
      {  "/get/bar",     "/get/bar",     "/get/bar",     "/get/bar",             nil       },
      {  "/get/bar",     "/get/bar/",    "/get/bar/",    "/get/bar/",            nil       },
      {  "/get/bar/",    "/",            "/",            "/get/bar/",            nil       },
      {  "/get/bar/",    "/",            "/get/bar",     "/get/bar/get/bar",     nil       },
      {  "/get/bar/",    "/",            "/get/bar/",    "/get/bar/get/bar/",    nil       },
      {  "/get/bar/",    "/get/bar",     "/get/bar",     "/get/bar",             nil       },
      {  "/get/bar/",    "/get/bar/",    "/get/bar/",    "/get/bar/",            nil       },
      {  "/",            "/",            "/",            "/",                    true      },
      {  "/",            "/",            "/get/bar",     "/get/bar",             true      },
      {  "/",            "/",            "/get/bar/",    "/get/bar/",            true      },
      {  "/",            "/get/bar",     "/get/bar",     "/",                    true      },
      {  "/",            "/get/bar/",    "/get/bar/",    "/",                    true      },
      {  "/get/bar",     "/",            "/",            "/get/bar",             true      },
      {  "/get/bar",     "/",            "/get/bar",     "/get/bar/get/bar",     true      },
      {  "/get/bar",     "/",            "/get/bar/",    "/get/bar/get/bar/",    true      },
      {  "/get/bar",     "/get/bar",     "/get/bar",     "/get/bar",             true      },
      {  "/get/bar",     "/get/bar/",    "/get/bar/",    "/get/bar/",            true      },
      {  "/get/bar/",    "/",            "/",            "/get/bar/",            true      },
      {  "/get/bar/",    "/",            "/get/bar",     "/get/bar/get/bar",     true      },
      {  "/get/bar/",    "/",            "/get/bar/",    "/get/bar/get/bar/",    true      },
      {  "/get/bar/",    "/get/bar",     "/get/bar",     "/get/bar",             true      },
      {  "/get/bar/",    "/get/bar/",    "/get/bar/",    "/get/bar/",            true      },
      {  "/",            "/",            "/",            "/",                    false     },
      {  "/",            "/",            "/get/bar",     "/get/bar",             false     },
      {  "/",            "/",            "/get/bar/",    "/get/bar/",            false     },
      {  "/",            "/get/bar",     "/get/bar",     "/get/bar",             false     },
      {  "/",            "/get/bar/",    "/get/bar/",    "/get/bar/",            false     },
      {  "/get/bar",     "/",            "/",            "/get/bar",             false     },
      {  "/get/bar",     "/",            "/get/bar",     "/get/bar/get/bar",     false     },
      {  "/get/bar",     "/",            "/get/bar/",    "/get/bar/get/bar/",    false     },
      {  "/get/bar",     "/get/bar",     "/get/bar",     "/get/bar/get/bar",     false     },
      {  "/get/bar",     "/get/bar/",    "/get/bar/",    "/get/bar/get/bar/",    false     },
      {  "/get/bar/",    "/",            "/",            "/get/bar/",            false     },
      {  "/get/bar/",    "/",            "/get/bar",     "/get/bar/get/bar",     false     },
      {  "/get/bar/",    "/",            "/get/bar/",    "/get/bar/get/bar/",    false     },
      {  "/get/bar/",    "/get/bar",     "/get/bar",     "/get/bar/get/bar",     false     },
      {  "/get/bar/",    "/get/bar/",    "/get/bar/",    "/get/bar/get/bar/",    false     },
    }

    lazy_setup(function()
      helpers.dao:truncate_table("apis")

      for i, args in ipairs(checks) do
        assert(helpers.dao.apis:insert {
            name         = "localbin-" .. i,
            strip_uri    = args[5],
            upstream_url = helpers.mock_upstream_url .. args[1],
            uris         = {
              args[2],
            },
            hosts        = {
              "localbin-" .. i .. ".com",
            },
        })
      end

      helpers.dao:run_migrations()
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
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
