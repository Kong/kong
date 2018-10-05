local helpers    = require "spec.helpers"
local cjson      = require "cjson"

describe("PDK: service.request", function()
  local proxy_client
  local bp, db, dao

  setup(function()
    bp, db, dao = helpers.get_db_utils()
    assert(db:truncate("routes"))
    assert(db:truncate("services"))
    dao:truncate_table("plugins")
    dao:run_migrations()

    local service1 = bp.services:insert{
      protocol = "http",
      host     = "http.com",
      port     = 80,
    }

    local route1 = bp.routes:insert {
      hosts   = { "pdk_service_request.http.com" },
      service = service1
    }

    bp.plugins:insert {
      route_id = route1.id,
      name     = "pdk-service-request"
    }

    local service2 = bp.services:insert{
      protocol = "https",
      host     = "https.com",
      port     = 8443,
    }

    local route2 = bp.routes:insert {
      hosts   = { "pdk_service_request.https.com" },
      service = service2
    }

    bp.plugins:insert {
      route_id = route2.id,
      name     = "pdk-service-request"
    }


    local service3 = bp.services:insert{
      protocol = "http",
      host     = "NoN-N0orMALIZed.com",
      port     = 80,
    }

    local route3 = bp.routes:insert {
      hosts   = { "pdk_service_request.non_normalized.com" },
      service = service3
    }

    bp.plugins:insert {
      route_id = route3.id,
      name     = "pdk-service-request"
    }


    local service4 = bp.services:insert{
      protocol = "http",
      host     = "http.com",
      port     = 80,
      path     = "/up/path",
    }

    local route4_1 = bp.routes:insert {
      hosts   = { "pdk_service_request.http.strip_path.com" },
      paths   = { "/test" },
      strip_path = true,
      service = service4
    }

    local route4_2 = bp.routes:insert {
      hosts   = { "pdk_service_request.http.no_strip_path.com" },
      paths   = { "/test" },
      strip_path = false,
      service = service4
    }

    bp.plugins:insert {
      route_id = route4_1.id,
      name     = "pdk-service-request"
    }

    bp.plugins:insert {
      route_id = route4_2.id,
      name     = "pdk-service-request"
    }


    assert(helpers.start_kong({
      custom_plugins = "pdk-service-request",
      nginx_conf     = "spec/fixtures/custom_nginx.template",
    }))

    proxy_client = helpers.proxy_client()
  end)

  teardown(function()
    if proxy_client then
      proxy_client:close()
    end

    helpers.stop_kong()

    assert(db:truncate("routes"))
    assert(db:truncate("services"))
    dao:truncate_table("plugins")
  end)

  describe("- global", function()
    it("getters: GET on http service", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.http.com", ["user-agent"] = "PDK test", ["X-Foo-Header"] = "Hello" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("GET", json.method)
      assert.same("http", json.scheme)
      assert.same("http.com", json.host)
      assert.same(80, json.port)
      assert.same("/test", json.path)
      assert.same("", json.raw_query)
      assert.same({}, json.query)
      assert.same({}, json.query_max_2)
      assert.same({ host = "pdk_service_request.http.com", ["user-agent"] = "PDK test", ["x-foo-header"] = "Hello" }, json.headers)
      assert.same({ host = "pdk_service_request.http.com", ["user-agent"] = "PDK test" }, json.headers_max_2)
      assert.same({}, json.err)
    end)

    it("getters: DELETE on https service, sub-path, query parameters", function()
      local res = proxy_client:get("/test/sub?Foo=true&Bar=10&single", {
        method = "DELETE",
        headers = { Host = "pdk_service_request.https.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("DELETE", json.method)
      assert.same("https", json.scheme)
      assert.same("https.com", json.host)
      assert.same(8443, json.port)
      assert.same("/test/sub", json.path)
      assert.same("Foo=true&Bar=10&single", json.raw_query)
      assert.same({ Foo = "true", Bar = "10", single=true }, json.query)
      assert.same({ Foo = "true", Bar = "10" }, json.query_max_2)
      assert.same({}, json.err)
    end)
  end)

  describe("- get_scheme()", function()
    it("returns http for plain text requests", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.http.com" }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("http", json.scheme)
    end)

    it("returns https for TLS requests", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.https.com" }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("https", json.scheme)
    end)
  end)

  describe("- get_host()", function()
    it("returns upstream host", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.http.com" }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("http.com", json.host)
    end)

    it("returns normalized host", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.non_normalized.com" }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("non-n0ormalized.com", json.host)
    end)
  end)

  describe("- get_port()", function()
    it("returns port 1/2", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.http.com" }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(80, json.port)
    end)

    it("returns port 2/2", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.https.com" }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(8443, json.port)
    end)
  end)

  describe("- get_method()", function()
    it("returns method 1/3", function()
      local res = proxy_client:get("/test", {
        method = "POST",
        headers = { Host = "pdk_service_request.http.com" }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("POST", json.method)
    end)

    it("returns method 2/3", function()
      local res = proxy_client:get("/test", {
        method = "PUT",
        headers = { Host = "pdk_service_request.http.com" }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("PUT", json.method)
    end)

    it("returns method 3/3", function()
      local res = proxy_client:get("/test", {
        method = "GET",
        headers = { Host = "pdk_service_request.http.com" }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("GET", json.method)
    end)
  end)

  describe("- get_path()", function()
    it("returns path component of uri", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.http.com" }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("/test", json.path)
    end)

    it("returns at least slash", function()
      local res = proxy_client:get("/", {
        headers = { Host = "pdk_service_request.http.com" }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("/", json.path)
    end)

    it("returns non normalized path", function()
      local res = proxy_client:get("/test/Abc%20123%C3%B8/../test/.", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("/test/Abc%20123%C3%B8/../test/.", json.path)
    end)

    it("strips query string", function()
      local res = proxy_client:get("/test/demo?param=value", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("/test/demo", json.path)
    end)

    it("with strip_path=true", function()
      local res = proxy_client:get("/test/demo", {
        headers = { Host = "pdk_service_request.http.strip_path.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("/up/path/demo", json.path)
    end)

    it("with strip_path=false", function()
      local res = proxy_client:get("/test/demo", {
        headers = { Host = "pdk_service_request.http.no_strip_path.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("/up/path/test/demo", json.path)
    end)
  end)

  describe("- get_raw_query()", function()
    it("returns query component of uri", function()
      local res = proxy_client:get("/test?query", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("query", json.raw_query)
    end)

    it("returns empty string on missing query string", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("", json.raw_query)
    end)

    it("returns empty string with empty query string", function()
      local res = proxy_client:get("/test?", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("", json.raw_query)
    end)

    it("is not normalized", function()
      local res = proxy_client:get("/test?Abc%20123%C3%B8/../test/.", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("Abc%20123%C3%B8/../test/.", json.raw_query)
    end)
  end)

  describe("- get_query_arg()", function()
    it("returns first query arg when multiple is given with same name", function()
      local res = proxy_client:get("/test?Foo=1&Foo=2", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("1", json.query_foo)
    end)

    it("returns values from case-sensitive table", function()
      local res = proxy_client:get("/test?Foo=1&foo=2", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("1", json.query_foo)
      assert.same("2", json.query_lower_foo)
    end)

    it("returns nil when query argument is missing", function()
      local res = proxy_client:get("/test?Foo=1", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(nil, json.query_bar)
    end)

    it("returns true when query argument has no value", function()
      local res = proxy_client:get("/test?Foo", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(true, json.query_foo)
    end)

    it("returns empty string when query argument's value is empty", function()
      local res = proxy_client:get("/test?Foo=", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("", json.query_foo)
    end)

    it("returns nil when requested query arg does not fit in max_args", function()
      local args = {}
      for i = 1, 100 do
        args["arg-" .. i] = "test"
      end

      local args = ngx.encode_args(args)
      args = args .. "&Foo=test"

      local res = proxy_client:get("/test?" .. args, {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(nil, json.query_foo)
    end)
  end)

  describe("- get_query()", function()
    it("returns request query arguments", function()
      local res = proxy_client:get("/test?Foo=Hello&Bar=World&Accept=application%2Fjson&Accept=text%2Fhtml", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same( { Foo = "Hello", Bar = "World", Accept = { "application/json", "text/html" } }, json.query)
    end)

    it("returns request query arguments case-sensitive", function()
      local res = proxy_client:get("/test?Foo=Hello&foo=World&fOO=Too", {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same( { Foo = "Hello", foo = "World", fOO = "Too"}, json.query)
    end)

    it("fetches 100 query arguments by default", function()
      local args = {}
      for i = 1, 200 do
        args["arg-" .. i] = "test"
      end

      local args = ngx.encode_args(args)

      local res = proxy_client:get("/test?" .. args, {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local n = 0
      for _ in pairs(json.query) do
          n = n + 1
      end

      assert.same(100, n)
    end)

    it("fetches max_args argument", function()
      local args = {}
      for i = 1, 10 do
        args["arg-" .. i] = "test"
      end

      local args = ngx.encode_args(args)

      local res = proxy_client:get("/test?" .. args, {
        headers = { Host = "pdk_service_request.http.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local n = 0
      for _ in pairs(json.query_max_2) do
          n = n + 1
      end

      assert.same(2, n)
    end)
  end)

  describe("- get_header()", function()
    it("returns first header when multiple is given with same name", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.http.com",
                    ["X-Foo-Header"] = { "Hello", "World" } }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("Hello", json.header_foo)
    end)

    it("returns values from case-insensitive metatable", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.http.com",
                    ["X-Foo-Header"] = "Hello" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("Hello", json.header_foo)
      assert.same("Hello", json.header_lower_foo)
      assert.same("Hello", json.header_underscode_foo)
    end)

    it("returns nil when header is missing", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.http.com",
                    ["X-Foo-Header"] = "Hello" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(nil, json.header_bar)
    end)

    it("returns empty string when header has no value", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.http.com",
                    ["X-Foo-Header"] = "" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("", json.header_foo)
    end)

    it("returns nil when requested header does not fit in default max_headers", function()
      local headers = {}
      for i = 1, 100 do
        headers["X-Header-" .. i] = "test"
      end

      headers.Host = "pdk_service_request.http.com"
      headers["X-Foo-Header"] = "test"

      local res = proxy_client:get("/test", {
        headers = headers
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(nil, json.header_foo)
    end)
  end)

  describe("- get_headers()", function()
    it("returns request headers", function()
      local res = proxy_client:get("/test", {
        headers = { Host = "pdk_service_request.http.com",
                    ["X-Foo-Header"] = "Hello", ["X-Bar-Header"] = "World",
                    Accept = { "application/json", "text/html" }, ["user-agent"] = "" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same({ host = "pdk_service_request.http.com",
                    ["x-foo-header"] = "Hello", ["x-bar-header"] = "World",
                    accept = { "application/json", "text/html" }, ["user-agent"] = "" }, json.headers)
    end)

    it("fetches 100 headers max by default", function()
      local headers = {}
      for i = 1, 200 do
        headers["X-Header-" .. i] = "test"
      end

      headers.Host = "pdk_service_request.http.com"

      local res = proxy_client:get("/test", {
        headers = headers
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local n = 0
      for _ in pairs(json.headers) do
          n = n + 1
      end

      assert.same(100, n)
    end)

    it("fetches max_headers argument", function()
      local headers = {}
      for i = 1, 10 do
        headers["X-Header-" .. i] = "test"
      end

      headers.Host = "pdk_service_request.http.com"

      local res = proxy_client:get("/test", {
        headers = headers
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local n = 0
      for _ in pairs(json.headers_max_2) do
          n = n + 1
      end

      assert.same(2, n)
    end)

  end)
end)
