local helpers = require "spec.helpers"
local random = require "resty.random"
local rstring = require "resty.string"

-- HTTP 1.1 Chunked Body (5 MB)
local function chunked_random_body()
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
          body = chunked_random_body(),
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
          body = chunked_random_body(),
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
          body = chunked_random_body(),
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
          body = chunked_random_body(),
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


if false then
  -- TODO: needs Lua cURL and that needs curl headers
  -- TODO: removed because it makes tests red on master
  local curl = require("cURL") -- luacheck: ignore


  --- Curl HTTP Body (5 MB)
  local function ramdom_body()
    return rstring.to_hex(random.bytes(5*1024*1024/2))
  end


  local HTTP_VERSIONS = {
    CURL_HTTP_VERSION_NONE = 0,
    CURL_HTTP_VERSION_1_0 = 1,
    CURL_HTTP_VERSION_1_1 = 2,
    CURL_HTTP_VERSION_2_0 = 3,
    CURL_HTTP_VERSION_2TLS = 4,
    CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE = 5
  }


  local function curl_post(url, body, http_version)
    http_version = http_version or HTTP_VERSIONS["CURL_HTTP_VERSION_2_0"]

    local c = curl.easy{
      url = url,
      ssl_verifypeer = false,
      ssl_verifyhost = false,
      post = true,
      postfields = body,
      --[curl.OPT_VERBOSE] = true,
      [curl.OPT_HEADER] = true,
      [curl.OPT_HTTP_VERSION] = http_version,
    }
    local response = {}
    c:setopt_writefunction(table.insert, response)
    c:perform()

    local status  = c:getinfo_response_code()
    local full_response = table.concat(response)
    local raw_headers = string.sub(full_response, 1, c:getinfo(curl.INFO_HEADER_SIZE))
    local return_body = string.sub(full_response, c:getinfo(curl.INFO_HEADER_SIZE))

    --parse headers
    local return_headers = {}
    for header in string.gmatch(raw_headers, "[%w%-]+:[^\n]+") do
      local index = string.find(header, ":")
      return_headers[string.lower(string.sub(header, 1, index-1))] = string.sub(header, index+2)
    end

    return status, return_headers, return_body
  end


  for _, version in pairs({ "CURL_HTTP_VERSION_1_1", "CURL_HTTP_VERSION_2_0" }) do
    local http_version = HTTP_VERSIONS[version]
    for _, strategy in helpers.each_strategy() do
      describe("HTTP #" .. version .. " buffered requests/response [#" .. strategy .. "]", function()
        local warmup_client
        local base_url
        local proxy_ip
        local proxy_port

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
          warmup_client:close()
          helpers.stop_kong()
        end)

        before_each(function()
          proxy_ip = helpers.get_proxy_ip(true, true)
          proxy_port = helpers.get_proxy_port(true, true)
          warmup_client = helpers.proxy_client()
          base_url = "https://" .. proxy_ip .. ":" .. proxy_port
        end)

        describe("request latency", function()
          local buffered_latency
          local unbuffered_latency
          local unbuffered_request_latency
          local unbuffered_response_latency
          local status, headers, _

          it("is calculated for buffered", function()
            warmup_client:post("/buffered/post", { body = "warmup" })
            status, headers, _ = curl_post(
              base_url .. "/buffered/post", ramdom_body(),
              http_version
            )
            assert.equal(200, status)
            buffered_latency = tonumber(headers["x-kong-proxy-latency"])
            assert.is_number(buffered_latency)
          end)

          it("is calculated for unbuffered", function()
            warmup_client:post("/unbuffered/post", { body = "warmup" })
            status, headers, _ = curl_post(
              base_url .. "/unbuffered/post", ramdom_body(),
              http_version
            )
            assert.equal(200, status)
            unbuffered_latency = tonumber(headers["x-kong-proxy-latency"])
            assert.is_number(unbuffered_latency)
          end)

          it("is calculated for unbuffered request", function()
            warmup_client:post("/unbuffered-request/post", { body = "warmup" })
            status, headers, _ = curl_post(
              base_url .. "/unbuffered-request/post", ramdom_body(),
              http_version
            )
            assert.equal(200, status)
            unbuffered_request_latency = tonumber(headers["x-kong-proxy-latency"])
            assert.is_number(unbuffered_request_latency)
          end)

          it("is calculated for unbuffered response", function()
            warmup_client:post("/unbuffered-response/post", { body = "warmup" })
            status, headers, _ = curl_post(
              base_url .. "/unbuffered-response/post", ramdom_body(),
              http_version
            )
            assert.equal(200, status)
            unbuffered_response_latency = tonumber(headers["x-kong-proxy-latency"])
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
      end)
    end
  end
end
