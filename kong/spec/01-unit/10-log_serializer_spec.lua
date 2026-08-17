require("spec.helpers")


local LOG_PHASE = require("kong.pdk.private.phases").phases.log


describe("kong.log.serialize", function()
  describe("#http", function()
    before_each(function()
      _G.ngx = {
        config = {
          subsystem = "http",
        },
        ctx = {
          balancer_data = {
            tries = {
              {
                ip = "127.0.0.1",
                port = 8000,
              },
            },
          },
          KONG_PROXIED = true,
          KONG_RECEIVE_TIME = 100,
          KONG_PROXY_LATENCY = 200,
        },
        var = {
          kong_request_id = "1234",
          request_uri = "/request_uri",
          upstream_uri = "/upstream_uri",
          scheme = "http",
          host = "test.test",
          server_port = "80",
          request_length = "200",
          bytes_sent = "99",
          request_time = "2",
          remote_addr = "1.1.1.1",
          -- may be a non-numeric string,
          -- see http://nginx.org/en/docs/http/ngx_http_upstream_module.html#var_upstream_addr
          upstream_status = "500, 200 : 200, 200",
        },
        update_time = ngx.update_time,
        sleep = ngx.sleep,
        time = ngx.time,
        req = {
          get_uri_args = function() return {"arg1", "arg2"} end,
          get_method = function() return "POST" end,
          get_headers = function() return {header1 = "header1", header2 = "header2", authorization = "authorization"} end,
          start_time = function() return 3 end,
        },
        resp = {
          get_headers = function() return {header1 = "respheader1", header2 = "respheader2", ["set-cookie"] = "delicious=delicacy"} end
        },
        get_phase = function() return "access" end,
      }

      package.loaded["kong.observability.tracing.request_id"] = nil
      package.loaded["kong.pdk.log"] = nil
      kong.log = require "kong.pdk.log".new(kong)

      package.loaded["kong.pdk.request"] = nil
      local pdk_request = require "kong.pdk.request"
      kong.request = pdk_request.new(kong)
      ngx.ctx.KONG_PHASE = LOG_PHASE
    end)

    describe("Basic", function()
      it("serializes without API, Consumer or Authenticated entity", function()
        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        -- Simple properties
        assert.equals("1.1.1.1", res.client_ip)
        assert.equals(3000, res.started_at)

        -- Latencies
        assert.is_table(res.latencies)
        assert.equal(200, res.latencies.kong)
        assert.equal(-1, res.latencies.proxy)
        assert.equal(2000, res.latencies.request)
        assert.equal(100, res.latencies.receive)

        -- Request
        assert.is_table(res.request)
        assert.same({header1 = "header1", header2 = "header2", authorization = "REDACTED"}, res.request.headers)
        assert.equal("POST", res.request.method)
        assert.same({"arg1", "arg2"}, res.request.querystring)
        assert.equal("http://test.test:80/request_uri", res.request.url)
        assert.equal("/upstream_uri", res.upstream_uri)
        assert.equal("500, 200 : 200, 200", res.upstream_status)
        assert.equal(200, res.request.size)
        assert.equal("/request_uri", res.request.uri)
        assert.equal("1234", res.request.id)

        -- Response
        assert.is_table(res.response)
        assert.same({header1 = "respheader1", header2 = "respheader2", ["set-cookie"] = "delicious=delicacy"}, res.response.headers)
        assert.equal(99, res.response.size)

        assert.is_nil(res.api)
        assert.is_nil(res.consumer)
        assert.is_nil(res.authenticated_entity)

        -- Tries
        assert.is_table(res.tries)

        assert.equal("upstream", res.source)
      end)

      it("uses port map (ngx.ctx.host_port) for request url ", function()
        ngx.ctx.host_port = 5000
        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)
        assert.is_table(res.request)
        assert.equal("http://test.test:5000/request_uri", res.request.url)
      end)

      it("serializes the matching Route and Services", function()
        ngx.ctx.route = { id = "my_route" }
        ngx.ctx.service = { id = "my_service" }

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        assert.equal("my_route", res.route.id)
        assert.equal("my_service", res.service.id)
        assert.is_nil(res.consumer)
        assert.is_nil(res.authenticated_entity)
      end)

      it("serializes the Consumer object", function()
        ngx.ctx.authenticated_consumer = { id = "someconsumer" }

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        assert.equal("someconsumer", res.consumer.id)
        assert.is_nil(res.api)
        assert.is_nil(res.authenticated_entity)
      end)

      it("serializes the Authenticated Entity object", function()
        ngx.ctx.authenticated_credential = {id = "somecred",
                                            consumer_id = "user1"}

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        assert.same({id = "somecred", consumer_id = "user1"},
                    res.authenticated_entity)
        assert.is_nil(res.consumer)
        assert.is_nil(res.api)
      end)

      it("serializes the tries and failure information", function()
        ngx.ctx.balancer_data.tries = {
          { ip = "127.0.0.1", port = 1234, state = "next",   code = 502 },
          { ip = "127.0.0.1", port = 1234, state = "failed", code = nil },
          { ip = "127.0.0.1", port = 1234 },
        }

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        assert.same({
            {
              code  = 502,
              ip    = '127.0.0.1',
              port  = 1234,
              state = 'next',
            }, {
              ip    = '127.0.0.1',
              port  = 1234,
              state = 'failed',
            }, {
              ip    = '127.0.0.1',
              port  = 1234,
            },
          }, res.tries)
      end)

      it("serializes the response.source", function()
        ngx.ctx.KONG_EXITED = true
        ngx.ctx.KONG_PROXIED = nil
        ngx.ctx.KONG_UNEXPECTED = nil

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)
        assert.same("kong", res.source)

        ngx.ctx.KONG_UNEXPECTED = nil
        ngx.ctx.KONG_EXITED = nil
        ngx.ctx.KONG_PROXIED = nil

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)
        assert.same("kong", res.source)
      end)

      it("does not fail when the 'balancer_data' structure is missing", function()
        ngx.ctx.balancer_data = nil

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        assert.is_nil(res.tries)
      end)

      it("includes query args in upstream_uri when they are not found in " ..
         "var.upstream_uri and exist in var.args", function()
        local args = "arg1=foo&arg2=bar"
        ngx.var.is_args = "?"
        ngx.var.args = args

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        assert.equal("/upstream_uri" .. "?" .. args, res.upstream_uri)
      end)

      it("use the deep copies of the Route, Service, Consumer object avoid " ..
         "modify ctx.authenticated_consumer, ctx.route, ctx.service", function()
        ngx.ctx.authenticated_consumer = { id = "someconsumer" }
        ngx.ctx.route = { id = "my_route" }
        ngx.ctx.service = { id = "my_service" }
        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.not_equal(tostring(ngx.ctx.authenticated_consumer),
                         tostring(res.consumer))
        assert.not_equal(tostring(ngx.ctx.route),
                         tostring(res.route))
        assert.not_equal(tostring(ngx.ctx.service),
                         tostring(res.service))
      end)

      it("handle 'json.null' and 'cdata null'", function()
        kong.log.set_serialize_value("response.body", ngx.null)
        local pok, value = pcall(kong.log.serialize, {})
        assert.is_true(pok)
        assert.is_true(type(value) == "table")

        local ffi = require "ffi"
        local n = ffi.new("void*")
        kong.log.set_serialize_value("response.body", n)
        local pok, value = pcall(kong.log.serialize, {})
        assert.is_false(pok)
        assert.is_true(type(value) == "string")
      end)
    end)
  end)

  describe("#stream", function()
    before_each(function()
      _G.ngx = {
        config = {
          subsystem = "stream",
          is_console = true,
        },
        ctx = {
          balancer_data = {
            tries = {
              {
                ip = "127.0.0.1",
                port = 8000,
              },
            },
          },
        },
        var = {
          bytes_received = "99",
          bytes_sent = "100",
          upstream_bytes_received = "200",
          upstream_bytes_sent = "300",
          session_time = "2.123",
          remote_addr = "1.1.1.1",
          server_port = "12345"
        },
        update_time = ngx.update_time,
        sleep = ngx.sleep,
        time = ngx.time,
        req = {
          start_time = function() return 3 end
        },
        status = 200,
      }

      package.loaded["kong.pdk.request"] = nil
      local pdk_request = require "kong.pdk.request"
      kong.request = pdk_request.new(kong)
      ngx.ctx.KONG_PHASE = LOG_PHASE

      -- reload log module, after ngx.config.subsystem has been patched
      -- to make sure the correct variant is used
      package.loaded["kong.pdk.log"] = nil
      local pdk_log = require "kong.pdk.log"
      kong.log = pdk_log.new(kong)
    end)

    describe("Basic", function()
      it("serializes without API, Consumer or Authenticated entity", function()
        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        -- Simple properties
        assert.equals("1.1.1.1", res.client_ip)
        assert.equals(3000, res.started_at)

        -- Latencies
        assert.is_table(res.latencies)
        assert.equal(0, res.latencies.kong)
        assert.equal(2123, res.latencies.session)

        -- Session
        assert.is_table(res.session)
        assert.equal(99, res.session.received)
        assert.equal(100, res.session.sent)
        assert.equal(200, res.session.status)
        assert.equal(12345, res.session.server_port)

        -- Upstream
        assert.is_table(res.upstream)
        assert.equal(300, res.upstream.sent)
        assert.equal(200, res.upstream.received)

        assert.is_nil(res.api)
        assert.is_nil(res.consumer)
        assert.is_nil(res.authenticated_entity)

        -- Tries
        assert.is_table(res.tries)
      end)

      it("serializes the matching Route and Services", function()
        ngx.ctx.route = { id = "my_route" }
        ngx.ctx.service = { id = "my_service" }

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        assert.equal("my_route", res.route.id)
        assert.equal("my_service", res.service.id)
        assert.is_nil(res.consumer)
        assert.is_nil(res.authenticated_entity)
      end)

      it("serializes the Consumer object", function()
        ngx.ctx.authenticated_consumer = { id = "someconsumer" }

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        assert.equal("someconsumer", res.consumer.id)
        assert.is_nil(res.api)
        assert.is_nil(res.authenticated_entity)
      end)

      it("serializes the Authenticated Entity object", function()
        ngx.ctx.authenticated_credential = {id = "somecred",
                                            consumer_id = "user1"}

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        assert.same({id = "somecred", consumer_id = "user1"},
                    res.authenticated_entity)
        assert.is_nil(res.consumer)
        assert.is_nil(res.api)
      end)

      it("serializes the tries and failure information", function()
        ngx.ctx.balancer_data.tries = {
          { ip = "127.0.0.1", port = 1234, state = "next",   code = 502 },
          { ip = "127.0.0.1", port = 1234, state = "failed", code = nil },
          { ip = "127.0.0.1", port = 1234 },
        }

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        assert.same({
            {
              code  = 502,
              ip    = '127.0.0.1',
              port  = 1234,
              state = 'next',
            }, {
              ip    = '127.0.0.1',
              port  = 1234,
              state = 'failed',
            }, {
              ip    = '127.0.0.1',
              port  = 1234,
            },
          }, res.tries)
      end)

      it("does not fail when the 'balancer_data' structure is missing", function()
        ngx.ctx.balancer_data = nil

        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)

        assert.is_nil(res.tries)
      end)

      it("use the deep copies of the Route, Service, Consumer object avoid " ..
         "modify ctx.authenticated_consumer, ctx.route, ctx.service", function()
        ngx.ctx.authenticated_consumer = { id = "someconsumer "}
        ngx.ctx.route = { id = "my_route" }
        ngx.ctx.service = { id = "my_service" }
        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.not_equal(tostring(ngx.ctx.authenticated_consumer),
                         tostring(res.consumer))
        assert.not_equal(tostring(ngx.ctx.route),
                         tostring(res.route))
        assert.not_equal(tostring(ngx.ctx.service),
                         tostring(res.service))
      end)
    end)
  end)
end)
