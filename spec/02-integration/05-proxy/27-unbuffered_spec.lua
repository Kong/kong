local helpers = require "spec.helpers"
local random = require "resty.random"
local rstring = require "resty.string"
local cjson = require "cjson"

local timeout = 60000

-- HTTP 1.1 Chunked Body (5 MB)
local function body()
  local chunk = "2000" .."\r\n" .. rstring.to_hex(random.bytes(4096)) .. "\r\n"
  local i = 0
  return function()
    i = i + 1

    if i == 641 then
      return "0\r\n\r\n"
    end

    if i == 642 then
      return nil
    end

    return chunk
  end
end


--- HTTP 2.0 Body (5 MB)
--- Chunked body's are not really supported by HTTP/2.0
--- But lua-http converts the chunks into HTTP/2.0 compatible data frames
local function body2()
  return rstring.to_hex(random.bytes(100))
end

for _, strategy in helpers.each_strategy() do
  describe("HTTP 1.1 Chunked [#" .. strategy .. "]", function()
    local proxy_client
    local warmup_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services"
      })

      local service = bp.services:insert()

      bp.routes:insert({
        protocols = { "http", "https" },
        paths = { "/buffered" },
        request_buffering = true,
        response_buffering = true,
        service = service,
      })

      bp.routes:insert({
        protocols = { "http", "https" },
        paths = { "/unbuffered" },
        request_buffering = false,
        response_buffering = false,
        service = service,
      })

      bp.routes:insert({
        protocols = { "http", "https" },
        paths = { "/unbuffered-request" },
        request_buffering = false,
        response_buffering = true,
        service = service,
      })

      bp.routes:insert({
        protocols = { "http", "https" },
        paths = { "/unbuffered-response" },
        request_buffering = true,
        response_buffering = false,
        service = service,
      })

      assert(helpers.start_kong {
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      warmup_client = helpers.proxy_client()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function ()
      warmup_client:close()
      proxy_client:close()
    end)

    describe("request latency", function()
      local buffered_latency
      local unbuffered_latency
      local unbuffered_request_latency
      local unbuffered_response_latency

      it("is calculated for buffered", function()
        warmup_client:post("/buffered/post", { body = "warmup" })

        local res = proxy_client:send({
          method = "POST",
          path = "/buffered/post",
          body = body(),
          headers = {
            ["Transfer-Encoding"] = "chunked",
            ["Content-Type"] = "application/octet-stream",
          }
        })

        assert.equal(200, res.status)

        buffered_latency = tonumber(res.headers["X-Kong-Proxy-Latency"])

        assert.is_number(buffered_latency)
      end)

      it("is calculated for unbuffered", function()
        warmup_client:post("/unbuffered/post", { body = "warmup" })

        local res = proxy_client:send({
          method = "POST",
          path = "/unbuffered/post",
          body = body(),
          headers = {
            ["Transfer-Encoding"] = "chunked",
            ["Content-Type"] = "application/octet-stream",
          }
        })

        assert.equal(200, res.status)

        unbuffered_latency = tonumber(res.headers["X-Kong-Proxy-Latency"])

        assert.is_number(unbuffered_latency)
      end)

      it("is calculated for unbuffered request", function()
        warmup_client:post("/unbuffered-request/post", { body = "warmup" })

        local res = proxy_client:send({
          method = "POST",
          path = "/unbuffered-request/post",
          body = body(),
          headers = {
            ["Transfer-Encoding"] = "chunked",
            ["Content-Type"] = "application/octet-stream",
          }
        })

        assert.equal(200, res.status)

        unbuffered_request_latency = tonumber(res.headers["X-Kong-Proxy-Latency"])

        assert.is_number(unbuffered_request_latency)
      end)

      it("is calculated for unbuffered response", function()
        warmup_client:post("/unbuffered-response/post", { body = "warmup" })

        local res = proxy_client:send({
          method = "POST",
          path = "/unbuffered-response/post",
          body = body(),
          headers = {
            ["Transfer-Encoding"] = "chunked",
            ["Content-Type"] = "application/octet-stream",
          }
        })

        assert.equal(200, res.status)

        unbuffered_response_latency = tonumber(res.headers["X-Kong-Proxy-Latency"])

        assert.is_number(unbuffered_response_latency)
      end)

      it("is greater for buffered than unbuffered", function()
        assert.equal(true, buffered_latency > unbuffered_latency)
      end)

      it("is greater for buffered than unbuffered request", function()
        assert.equal(true, buffered_latency > unbuffered_request_latency)
      end)

      it("is greater for unbuffered response than unbuffered", function()
        assert.equal(true, unbuffered_response_latency > unbuffered_latency)
      end)

      it("is greater for unbuffered response than unbuffered request", function()
        assert.equal(true, unbuffered_response_latency > unbuffered_request_latency)
      end)
    end)

    describe("number of response chunks", function()
      local buffered_chunks = 0
      local unbuffered_chunks = 0
      local unbuffered_request_chunks = 0
      local unbuffered_response_chunks = 0

      it("is calculated for buffered", function()
        warmup_client:get("/buffered/stream/1")

        local res = proxy_client:get("/buffered/stream/1000")

        assert.equal(200, res.status)

        local reader = res.body_reader

        repeat
          local chunk, err = reader(8192 * 640)

          assert.equal(nil, err)

          if chunk then
            buffered_chunks = buffered_chunks + 1
          end
        until not chunk
      end)

      it("is calculated for unbuffered", function()
        warmup_client:get("/unbuffered/stream/1")

        local res = proxy_client:get("/unbuffered/stream/1000")

        assert.equal(200, res.status)

        local reader = res.body_reader

        repeat
          local chunk, err = reader(8192 * 640)

          assert.equal(nil, err)

          if chunk then
            unbuffered_chunks = unbuffered_chunks + 1
          end
        until not chunk
      end)

      it("is calculated for unbuffered request", function()
        warmup_client:get("/unbuffered-request/stream/1")

        local res = proxy_client:get("/unbuffered-request/stream/1000")

        assert.equal(200, res.status)

        local reader = res.body_reader

        repeat
          local chunk, err = reader(8192 * 640)

          assert.equal(nil, err)

          if chunk then
            unbuffered_request_chunks = unbuffered_request_chunks + 1
          end
        until not chunk
      end)

      it("is calculated for unbuffered response", function()
        warmup_client:get("/unbuffered-response/stream/1")

        local res = proxy_client:get("/unbuffered-response/stream/1000")

        assert.equal(200, res.status)

        local reader = res.body_reader

        repeat
          local chunk, err = reader(8192 * 640)

          assert.equal(nil, err)

          if chunk then
            unbuffered_response_chunks = unbuffered_response_chunks + 1
          end
        until not chunk
      end)

      it("is greater for unbuffered than buffered", function()
        assert.equal(true, unbuffered_chunks > buffered_chunks)
      end)

      it("is greater for unbuffered than unbuffered request", function()
        assert.equal(true, unbuffered_chunks > unbuffered_request_chunks)
      end)

      it("is greater for unbuffered response than buffered", function()
        assert.equal(true, unbuffered_response_chunks > buffered_chunks)
      end)

      it("is greater for unbuffered response than unbuffered request", function()
        assert.equal(true, unbuffered_response_chunks > unbuffered_request_chunks)
      end)
    end)
  end)
end


-- Tests for HTTP/2.0
for _, strategy in helpers.each_strategy() do
  describe("HTTP 2.0 Buffered requests/response [#" .. strategy .. "]", function()
    local proxy_client
    local warmup_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services"
      })

      local service = bp.services:insert()

      bp.routes:insert({
        protocols = { "http", "https" },
        paths = { "/buffered" },
        request_buffering = true,
        response_buffering = true,
        service = service,
      })

      bp.routes:insert({
        protocols = { "http", "https" },
        paths = { "/unbuffered" },
        request_buffering = false,
        response_buffering = false,
        service = service,
      })

      bp.routes:insert({
        protocols = { "http", "https" },
        paths = { "/unbuffered-request" },
        request_buffering = false,
        response_buffering = true,
        service = service,
      })

      bp.routes:insert({
        protocols = { "http", "https" },
        paths = { "/unbuffered-response" },
        request_buffering = true,
        response_buffering = false,
        service = service,
      })

      assert(helpers.start_kong {
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_ip = helpers.get_proxy_ip(true, true)
      proxy_port = helpers.get_proxy_port(true, true)
      warmup_client = helpers.http2_client(proxy_ip, proxy_port, true)
      proxy_client = helpers.http2_client(proxy_ip, proxy_port, true)
    end)

    describe("request latency", function()
      local buffered_latency
      local unbuffered_latency
      local unbuffered_request_latency
      local unbuffered_response_latency

      it("is calculated for buffered", function()
        print("PJ0")
        local res, headers = assert(warmup_client {
          headers = {
            [":method"] = "POST",
            [":path"] = "/buffered/post",
          },
          body = "warmup"
        })
        assert.equal('200', headers:get ":status")

        local res, headers = assert(proxy_client {
          headers = {
            [":method"] = "POST",
            [":path"] = "/buffered/post",
            ["content-type"] = "application/octet-stream",
          },
          timeout = 10,
          body = body2()
        })

        local json = cjson.decode(res)
        assert.equal('200', headers:get ":status")
        print("HEADERS")
        for name, value, never_index in headers:each() do
          print(name, " ", value)
        end
        buffered_latency = tonumber(headers:get("x-kong-proxy-latency"))
        assert.is_number(buffered_latency)
      end)

    --   it("is calculated for unbuffered", function()
    --     warmup_client:post("/unbuffered/post", { body = "warmup" })

    --     local res = proxy_client:send({
    --       method = "POST",
    --       path = "/unbuffered/post",
    --       body = body(),
    --       headers = {
    --         ["Transfer-Encoding"] = "chunked",
    --         ["Content-Type"] = "application/octet-stream",
    --       }
    --     })

    --     assert.equal(200, res.status)

    --     unbuffered_latency = tonumber(res.headers["X-Kong-Proxy-Latency"])

    --     assert.is_number(unbuffered_latency)
    --   end)

    --   it("is calculated for unbuffered request", function()
    --     warmup_client:post("/unbuffered-request/post", { body = "warmup" })

    --     local res = proxy_client:send({
    --       method = "POST",
    --       path = "/unbuffered-request/post",
    --       body = body(),
    --       headers = {
    --         ["Transfer-Encoding"] = "chunked",
    --         ["Content-Type"] = "application/octet-stream",
    --       }
    --     })

    --     assert.equal(200, res.status)

    --     unbuffered_request_latency = tonumber(res.headers["X-Kong-Proxy-Latency"])

    --     assert.is_number(unbuffered_request_latency)
    --   end)

    --   it("is calculated for unbuffered response", function()
    --     warmup_client:post("/unbuffered-response/post", { body = "warmup" })

    --     local res = proxy_client:send({
    --       method = "POST",
    --       path = "/unbuffered-response/post",
    --       body = body(),
    --       headers = {
    --         ["Transfer-Encoding"] = "chunked",
    --         ["Content-Type"] = "application/octet-stream",
    --       }
    --     })

    --     assert.equal(200, res.status)

    --     unbuffered_response_latency = tonumber(res.headers["X-Kong-Proxy-Latency"])

    --     assert.is_number(unbuffered_response_latency)
    --   end)

    --   it("is greater for buffered than unbuffered", function()
    --     assert.equal(true, buffered_latency > unbuffered_latency)
    --   end)

    --   it("is greater for buffered than unbuffered request", function()
    --     assert.equal(true, buffered_latency > unbuffered_request_latency)
    --   end)

    --   it("is greater for unbuffered response than unbuffered", function()
    --     assert.equal(true, unbuffered_response_latency > unbuffered_latency)
    --   end)

    --   it("is greater for unbuffered response than unbuffered request", function()
    --     assert.equal(true, unbuffered_response_latency > unbuffered_request_latency)
    --   end)
    -- end)

    -- describe("number of response chunks", function()
    --   local buffered_chunks = 0
    --   local unbuffered_chunks = 0
    --   local unbuffered_request_chunks = 0
    --   local unbuffered_response_chunks = 0

    --   it("is calculated for buffered", function()
    --     warmup_client:get("/buffered/stream/1")

    --     local res = proxy_client:get("/buffered/stream/1000")

    --     assert.equal(200, res.status)

    --     local reader = res.body_reader

    --     repeat
    --       local chunk, err = reader(8192 * 640)

    --       assert.equal(nil, err)

    --       if chunk then
    --         buffered_chunks = buffered_chunks + 1
    --       end
    --     until not chunk
    --   end)

    --   it("is calculated for unbuffered", function()
    --     warmup_client:get("/unbuffered/stream/1")

    --     local res = proxy_client:get("/unbuffered/stream/1000")

    --     assert.equal(200, res.status)

    --     local reader = res.body_reader

    --     repeat
    --       local chunk, err = reader(8192 * 640)

    --       assert.equal(nil, err)

    --       if chunk then
    --         unbuffered_chunks = unbuffered_chunks + 1
    --       end
    --     until not chunk
    --   end)

    --   it("is calculated for unbuffered request", function()
    --     warmup_client:get("/unbuffered-request/stream/1")

    --     local res = proxy_client:get("/unbuffered-request/stream/1000")

    --     assert.equal(200, res.status)

    --     local reader = res.body_reader

    --     repeat
    --       local chunk, err = reader(8192 * 640)

    --       assert.equal(nil, err)

    --       if chunk then
    --         unbuffered_request_chunks = unbuffered_request_chunks + 1
    --       end
    --     until not chunk
    --   end)

    --   it("is calculated for unbuffered response", function()
    --     warmup_client:get("/unbuffered-response/stream/1")

    --     local res = proxy_client:get("/unbuffered-response/stream/1000")

    --     assert.equal(200, res.status)

    --     local reader = res.body_reader

    --     repeat
    --       local chunk, err = reader(8192 * 640)

    --       assert.equal(nil, err)

    --       if chunk then
    --         unbuffered_response_chunks = unbuffered_response_chunks + 1
    --       end
    --     until not chunk
    --   end)

    --   it("is greater for unbuffered than buffered", function()
    --     assert.equal(true, unbuffered_chunks > buffered_chunks)
    --   end)

    --   it("is greater for unbuffered than unbuffered request", function()
    --     assert.equal(true, unbuffered_chunks > unbuffered_request_chunks)
    --   end)

    --   it("is greater for unbuffered response than buffered", function()
    --     assert.equal(true, unbuffered_response_chunks > buffered_chunks)
    --   end)

    --   it("is greater for unbuffered response than unbuffered request", function()
    --     assert.equal(true, unbuffered_response_chunks > unbuffered_request_chunks)
    --   end)
     end)
  end)
end