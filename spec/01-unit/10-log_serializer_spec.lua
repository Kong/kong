require("spec.helpers")
local basic = require("kong.plugins.log-serializers.basic")
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
        },
        var = {
          request_uri = "/request_uri",
          upstream_uri = "/upstream_uri",
          scheme = "http",
          host = "test.com",
          server_port = "80",
          request_length = "200",
          bytes_sent = "99",
          request_time = "2",
          remote_addr = "1.1.1.1"
        },
        update_time = ngx.update_time,
        sleep = ngx.sleep,
        time = ngx.time,
        req = {
          get_uri_args = function() return {"arg1", "arg2"} end,
          get_method = function() return "POST" end,
          get_headers = function() return {header1 = "header1", header2 = "header2", authorization = "authorization"} end,
          start_time = function() return 3 end
        },
        resp = {
          get_headers = function() return {header1 = "respheader1", header2 = "respheader2", ["set-cookie"] = "delicious=delicacy"} end
        },
      }

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
        assert.equal(0, res.latencies.kong)
        assert.equal(-1, res.latencies.proxy)
        assert.equal(2000, res.latencies.request)

        -- Request
        assert.is_table(res.request)
        assert.same({header1 = "header1", header2 = "header2", authorization = "REDACTED"}, res.request.headers)
        assert.equal("POST", res.request.method)
        assert.same({"arg1", "arg2"}, res.request.querystring)
        assert.equal("http://test.com:80/request_uri", res.request.url)
        assert.equal("/upstream_uri", res.upstream_uri)
        assert.equal(200, res.request.size)
        assert.equal("/request_uri", res.request.uri)

        -- Response
        assert.is_table(res.response)
        assert.same({header1 = "respheader1", header2 = "respheader2", ["set-cookie"] = "delicious=delicacy"}, res.response.headers)
        assert.equal(99, res.response.size)

        assert.is_nil(res.api)
        assert.is_nil(res.consumer)
        assert.is_nil(res.authenticated_entity)

        -- Tries
        assert.is_table(res.tries)
      end)

      it("uses port map (ngx.ctx.host_port) for request url ", function()
        ngx.ctx.host_port = 5000
        local res = kong.log.serialize({ngx = ngx, kong = kong, })
        assert.is_table(res)
        assert.is_table(res.request)
        assert.equal("http://test.com:5000/request_uri", res.request.url)
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
        ngx.ctx.authenticated_consumer = {id = "someconsumer"}

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

      it("basic serializer proxy works with a deprecation warning", function()
        local warned = false
        local orig_warn = kong.log.warn

        kong.log.warn = function(msg)
          assert.is_false(warned, "duplicate warning")

          warned = true

          return orig_warn(msg)
        end

        local res = basic.serialize(ngx, kong)
        assert.is_table(res)

        assert.equals("1.1.1.1", res.client_ip)

        -- 2nd time
        res = basic.serialize(ngx, kong)
        assert.is_table(res)

        kong.log.warn = orig_warn
      end)
    end)
  end)

  describe("#stream", function()
    before_each(function()
      _G.ngx = {
        config = {
          subsystem = "stream",
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
        ngx.ctx.authenticated_consumer = {id = "someconsumer"}

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
    end)
  end)
end)
