-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local fixtures = {
  http_mock = {
    test = [[
      server {
          server_name example.com;
          listen 17777;
          client_body_buffer_size 1024m;

          location = /post {
              content_by_lua_block {
                  local function get_body_data()
                    ngx.req.read_body()
                    local data  = ngx.req.get_body_data()
                    if data then
                      return data
                    end

                    local file_path = ngx.req.get_body_file()
                    if file_path then
                      local file = io.open(file_path, "r")
                      data       = file:read("*all")
                      file:close()
                      return data
                    end

                    return ""
                  end

                  local body = get_body_data()
                  ngx.status = 200
                  ngx.header["X-Paylod-Md5"] = ngx.md5(body)
                  ngx.print(body)
              }
          }
      }
    ]]
  },
}


local function chunked_body(chunksize, n)
  local data = string.rep("a", chunksize)
  local chunk = string.format("%x", chunksize) .."\r\n" .. data .. "\r\n"
  local i = 0
  return function()
    i = i + 1

    if i == n + 1 then
      return "0\r\n\r\n"
    end

    if i == n + 2 then
      return nil
    end

    return chunk
  end
end

for _, strategy in helpers.each_strategy() do
  describe("proxy", function()
    local proxy_client
    local proxy_http2_client
    local configuration = {
      log_level = "debug",
      database = strategy,
      plugins = "forward-proxy,pre-function",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      nginx_http_client_body_buffer_size = "1k",
      nginx_http_client_max_body_size = "1m",
      untrusted_lua = "on",
    }

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, { "routes", "servcies", "plugins" }, { "forward-proxy", "pre-function" })

      local service = bp.services:insert {
        host = "example.com",
        protocol = "http",
        port = 80,
      }

      local route = assert(bp.routes:insert {
        hosts = { "service.com" },
        service = service,
      })

      assert(bp.plugins:insert {
        route = { id = route.id },
        name = "forward-proxy",
        config = {
          http_proxy_host = "localhost",
          http_proxy_port = 17777,
        },
      })

      local route_patch = assert(bp.routes:insert {
        hosts = { "service-patch.com" },
        service = service,
      })

      assert(bp.plugins:insert {
        route = { id = route_patch.id },
        name = "forward-proxy",
        config = {
          http_proxy_host = "localhost",
          http_proxy_port = 17777,
        },
      })
      assert(bp.plugins:insert {
        route = { id = route_patch.id },
        name = "pre-function",
        config = {
          access = {
            [[
io.open = function(filename, mode)
  local mocker = {}
  function mocker:read(n)
    self.count = self.count + 1
    if self.count >= 10 then
      return nil
    else
      return string.rep("a", 10)
    end
  end
  function mocker:seek(whence, offset)
    if whence == "end" then
      return 1000
    end
    return 0
  end
  function mocker:close() end

  return setmetatable({ count = 0},  { __index = mocker })
end
          ]]
          },
        },
      })

      assert(helpers.start_kong(configuration, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    before_each(function()
      helpers.clean_logfile()
      proxy_client = helpers.proxy_client()
      proxy_http2_client = helpers.proxy_client_h2()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    describe("streaming proxy", function()

      it("application/json", function()
        local req_body = {
          key = string.rep("a", 1024 * 4)
        }
        local payload = cjson.encode(req_body)
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "service.com",
            ["Content-Type"] = "application/json",
          },
          body = payload
        })
        assert.res_status(200, res)
        assert.equal(ngx.md5(payload), res.headers["X-Paylod-Md5"])
        assert.logfile().has.line("forwarding request in a streaming manner")
      end)

      it("application/octet-stream", function()
        local bytes = {}
        for i = 1, 1024 * 4 do
          bytes[i] = string.char(math.random(0, 255))
        end
        local payload = table.concat(bytes)
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "service.com",
            ["Content-Type"] = "application/octet-stream",
          },
          body = payload
        })
        assert.res_status(200, res)
        assert.equal(ngx.md5(payload), res.headers["X-Paylod-Md5"])
        assert.logfile().has.line("forwarding request in a streaming manner")
      end)

      it("request payload exceed max_body_size", function()
        local req_body = {
          key = string.rep("a", 1024 * 1024)
        }
        local payload = cjson.encode(req_body)
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "service.com",
            ["Content-Type"] = "application/json",
          },
          body = payload
        })
        assert.res_status(413, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("Payload too large", body.message)
      end)

    end)

    describe("non-streaming proxy", function()

      it("chunked encoding", function()
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "service.com",
            ["Transfer-Encoding"] = "chunked",
            ["Content-Type"] = "application/octet-stream",
          },
          body = chunked_body(1024, 10)
        })
        assert.res_status(200, res)
        assert.equal(ngx.md5(string.rep("a", 1024 * 10)), res.headers["X-Paylod-Md5"])
        assert.logfile().has.line("forwarding request in a non-streaming manner")
        assert.logfile().has.line("a client request body is buffered to a temporary file")
      end)

      it("HTTP/2", function()
        local payload = string.rep("a", 1024 * 1024)
        local body, headers = assert(proxy_http2_client {
          headers = {
            [":authority"] = "service.com",
            [":method"] = "POST",
            [":path"] = "/post",
          },
          body = payload
        })
        assert.equal(200, tonumber(headers:get(":status")))
        assert.equal(payload, body)
        assert.logfile().has.line("forwarding request in a non-streaming manner")
        assert.logfile().has.line("a client request body is buffered to a temporary file")
      end)

      it("quick fail when reading file has error", function()
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "service-patch.com",
            ["Transfer-Encoding"] = "chunked",
            ["Content-Type"] = "application/octet-stream",
          },
          body = chunked_body(1024, 10)
        })
        assert.res_status(500, res)
        assert.logfile().has.line("forwarding request in a non-streaming manner")
        assert.logfile().has.line("failed to send proxy request: reading file error")
      end)
    end)

    it("hornor nginx_http_client_body_buffer_size", function()
      configuration.nginx_http_client_body_buffer_size = "32m"
      helpers.restart_kong(configuration)
      assert.logfile().has.line("file reading buffer size is adapted to 32m based on nginx_http_client_body_buffer_size")

      -- exceed max size 64m
      configuration.nginx_http_client_body_buffer_size = "100m"
      helpers.restart_kong(configuration)
      assert.logfile().has.line("file reading buffer size is adapted to 64m based on nginx_http_client_body_buffer_size")

    end)
  end)

end

