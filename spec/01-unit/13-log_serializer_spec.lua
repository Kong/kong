local basic = require "kong.plugins.log-serializers.basic"

describe("Log Serializer", function()
  local ngx

  before_each(function()
    ngx = {
      ctx = {},
      var = {
        request_uri = "/request_uri",
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
  end)

  describe("Basic", function()
    it("serializes without API, Consumer or Authenticated entity", function()
      local res = basic.serialize(ngx)
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
      assert.equal("http://test.com:80/request_uri", res.request.request_uri)
      assert.equal(200, res.request.size)
      assert.equal("/request_uri", res.request.uri)

      -- Response
      assert.is_table(res.response)
      assert.same({"respheader1", "respheader2"}, res.response.headers)
      assert.equal(99, res.response.size)

      assert.is_nil(res.api)
      assert.is_nil(res.consumer)
      assert.is_nil(res.authenticated_entity)
    end)

    it("serializes the API object", function()
      ngx.ctx.api = {id = "someapi"}

      local res = basic.serialize(ngx)
      assert.is_table(res)

      assert.equal("someapi", res.api.id)
      assert.is_nil(res.consumer)
      assert.is_nil(res.authenticated_entity)
    end)

    it("serializes the Consumer object", function()
      ngx.ctx.authenticated_consumer = {id = "someconsumer"}

      local res = basic.serialize(ngx)
      assert.is_table(res)

      assert.equal("someconsumer", res.consumer.id)
      assert.is_nil(res.api)
      assert.is_nil(res.authenticated_entity)
    end)

    it("serializes the Authenticated Entity object", function()
      ngx.ctx.authenticated_credential = {id = "somecred", 
                                          consumer_id = "user1"}

      local res = basic.serialize(ngx)
      assert.is_table(res)

      assert.same({id = "somecred", consumer_id = "user1"},
                  res.authenticated_entity)
      assert.is_nil(res.consumer)
      assert.is_nil(res.api)
    end)
  end)
end)
