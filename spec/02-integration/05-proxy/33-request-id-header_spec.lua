local helpers = require "spec.helpers"
local constants = require "kong.constants"
local cjson = require "cjson"


local function setup_db()
  local bp = helpers.get_db_utils(nil, {
    "routes",
    "services",
    "plugins",
  })

  local service = bp.services:insert {
    host = helpers.mock_upstream_host,
    port = helpers.mock_upstream_port,
    protocol = helpers.mock_upstream_protocol,
  }

  bp.routes:insert {
    protocols = { "http" },
    hosts = { "request_id" },
    service = service,
  }

  local route_post_func = bp.routes:insert {
    protocols = { "http" },
    hosts = { "post-function-access" },
    service = service,
  }

  bp.plugins:insert {
    name = "post-function",
    route = route_post_func,
    config = { access = {
      "ngx.req.set_header('" .. constants.HEADERS.REQUEST_ID .. "', 'overwritten')"
    }}
  }

  local route_post_func_2 = bp.routes:insert {
    protocols = { "http" },
    hosts = { "post-function-header-filter" },
    service = service,
  }

  bp.plugins:insert {
    name = "post-function",
    route = route_post_func_2,
    config = { header_filter = {
      "ngx.header['" .. constants.HEADERS.REQUEST_ID .. "'] = 'overwritten'"
    }}
  }

end


describe(constants.HEADERS.REQUEST_ID .. " header", function()
  local client

  describe("(downstream)", function()
    describe("with default configuration", function()
      lazy_setup(function()
        setup_db()

        assert(helpers.start_kong {
          nginx_conf = "spec/fixtures/custom_nginx.template",
          plugins = "bundled",
        })

        client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if client then
          client:close()
        end

        helpers.stop_kong()
      end)

      it("contains the expected value", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "request_id",
          }
        })
        assert.res_status(200, res)
        assert.matches("^[0-9a-f]+$", res.headers[constants.HEADERS.REQUEST_ID])
      end)

      it("should be populated when no API matched", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "404.test",
          }
        })
        local body = assert.res_status(404, res)
        body = cjson.decode(body)

        assert.matches(body.message, "no Route matched with those values")
        assert.matches("^[0-9a-f]+$", res.headers[constants.HEADERS.REQUEST_ID])
      end)

      it("overwrites value set by plugin", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "post-function-header-filter",
          }
        })
        assert.res_status(200, res)

        local downstream_header = res.headers[constants.HEADERS.REQUEST_ID]
        assert.not_nil(downstream_header)
        assert.matches("^[0-9a-f]+$", downstream_header)
        assert.not_equal("overwritten", downstream_header)
      end)
    end)


    describe("with configuration [headers=X-Kong-Request-Id]", function()
      lazy_setup(function()
        setup_db()

        assert(helpers.start_kong {
          nginx_conf = "spec/fixtures/custom_nginx.template",
          headers = "X-Kong-Request-Id",
        })

        client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if client then
          client:close()
        end

        helpers.stop_kong()
      end)

      it("contains the expected value", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "request_id",
          }
        })
        assert.res_status(200, res)
        assert.matches("^[0-9a-f]+$", res.headers[constants.HEADERS.REQUEST_ID])
      end)
    end)

    describe("is not injected with configuration [headers=off]", function()
      lazy_setup(function()
        setup_db()

        assert(helpers.start_kong {
          nginx_conf = "spec/fixtures/custom_nginx.template",
          headers = "off",
        })

        client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if client then
          client:close()
        end

        helpers.stop_kong()
      end)

      it("is nil", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "request_id",
          }
        })
        assert.res_status(200, res)
        assert.is_nil(res.headers[constants.HEADERS.REQUEST_ID])
      end)
    end)
  end)

  describe("(upstream)", function()
    describe("default configuration", function()
      lazy_setup(function()
        setup_db()

        assert(helpers.start_kong {
          nginx_conf = "spec/fixtures/custom_nginx.template",
          plugins = "bundled",
        })

        client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if client then
          client:close()
        end

        helpers.stop_kong()
      end)

      it("contains the expected value", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/anything",
          headers = {
            host = "request_id",
          }
        })
        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        assert.matches("^[0-9a-f]+$", body.headers[string.lower(constants.HEADERS.REQUEST_ID)])
      end)

      it("overwrites client value if any", function()
        local client_header_value = "client_value"
        local res = assert(client:send {
          method  = "GET",
          path    = "/anything",
          headers = {
            host = "request_id",
            ["X-Kong-Request-Id"] = client_header_value
          }
        })

        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        local upstream_received_header = body.headers[string.lower(constants.HEADERS.REQUEST_ID)]

        assert.matches("^[0-9a-f]+$", upstream_received_header)
        assert.not_equal(client_header_value, upstream_received_header)
      end)

      it("overwrites value set by plugin", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "post-function-access",
          }
        })

        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        local upstream_received_header = body.headers[string.lower(constants.HEADERS.REQUEST_ID)]

        assert.matches("^[0-9a-f]+$", upstream_received_header)
        assert.not_equal("overwritten", upstream_received_header)
      end)
    end)


    describe("is injected with configuration [headers=X-Kong-Request-Id]", function()
      lazy_setup(function()
        setup_db()

        assert(helpers.start_kong {
          nginx_conf = "spec/fixtures/custom_nginx.template",
          headers_upstream = "X-Kong-Request-Id",
        })

        client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if client then
          client:close()
        end

        helpers.stop_kong()
      end)

      it("contains the expected value", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "request_id",
          }
        })
        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        assert.matches("^[0-9a-f]+$", body.headers[string.lower(constants.HEADERS.REQUEST_ID)])
      end)
    end)


    describe("is not injected with configuration [headers=off]", function()
      lazy_setup(function()
        setup_db()

        assert(helpers.start_kong {
          nginx_conf = "spec/fixtures/custom_nginx.template",
          headers_upstream = "off",
        })

        client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if client then
          client:close()
        end

        helpers.stop_kong()
      end)

      it("is nil", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "request_id",
          }
        })
        local body = assert.res_status(200, res)
        body = cjson.decode(body)
        assert.is_nil(body.headers[string.lower(constants.HEADERS.REQUEST_ID)])
      end)
    end)
  end)
end)
