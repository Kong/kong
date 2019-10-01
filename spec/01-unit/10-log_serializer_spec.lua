require "spec.helpers"
local basic = require "kong.plugins.log-serializers.basic"

describe("Log Serializer", function()
  before_each(function()
    _G.ngx = {
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
        server_port = 80,
        request_length = 200,
        bytes_sent = 99,
        request_time = 2,
        remote_addr = "1.1.1.1"
      },
      req = {
        get_uri_args = function() return {"arg1", "arg2"} end,
        get_method = function() return "POST" end,
        get_headers = function() return {"header1", "header2"} end,
        start_time = function() return 3 end
      },
      resp = {
        get_headers = function() return {"respheader1", "respheader2"} end
      }
    }

    package.loaded["kong.pdk.request"] = nil
    local pdk_request = require "kong.pdk.request"
    kong.request = pdk_request.new(kong)
  end)

  describe("Basic", function()
    it("serializes without API, Consumer or Authenticated entity", function()
      local res = basic.serialize(ngx, kong)
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
      assert.same({"header1", "header2"}, res.request.headers)
      assert.equal("POST", res.request.method)
      assert.same({"arg1", "arg2"}, res.request.querystring)
      assert.equal("http://test.com:80/request_uri", res.request.url)
      assert.equal("/upstream_uri", res.upstream_uri)
      assert.equal(200, res.request.size)
      assert.equal("/request_uri", res.request.uri)

      -- Response
      assert.is_table(res.response)
      assert.same({"respheader1", "respheader2"}, res.response.headers)
      assert.equal(99, res.response.size)

      assert.is_nil(res.api)
      assert.is_nil(res.consumer)
      assert.is_nil(res.authenticated_entity)

      -- Tries
      assert.is_table(res.tries)
    end)

    it("serializes the matching Route and Services", function()
      ngx.ctx.route = { id = "my_route" }
      ngx.ctx.service = { id = "my_service" }

      local res = basic.serialize(ngx, kong)
      assert.is_table(res)

      assert.equal("my_route", res.route.id)
      assert.equal("my_service", res.service.id)
      assert.is_nil(res.consumer)
      assert.is_nil(res.authenticated_entity)
    end)

    it("serializes the Consumer object", function()
      ngx.ctx.authenticated_consumer = {id = "someconsumer"}

      local res = basic.serialize(ngx, kong)
      assert.is_table(res)

      assert.equal("someconsumer", res.consumer.id)
      assert.is_nil(res.api)
      assert.is_nil(res.authenticated_entity)
    end)

    it("serializes the Authenticated Entity object", function()
      ngx.ctx.authenticated_credential = {id = "somecred",
                                          consumer_id = "user1"}

      local res = basic.serialize(ngx, kong)
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

      local res = basic.serialize(ngx, kong)
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

      local res = basic.serialize(ngx, kong)
      assert.is_table(res)

      assert.is_nil(res.tries)
    end)
  end)
end)
