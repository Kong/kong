local helpers = require "spec.helpers"
local cjson = require "cjson"
local client

local function insert_apis(arr)
  if type(arr) ~= "table" then
    return error("expected arg #1 to be a table", 2)
  end

  helpers.dao:truncate_table("apis")

  for i = 1, #arr do
    assert(helpers.dao.apis:insert(arr[i]))
  end
end

local function start_kong(config)
  return function()
    insert_apis {
      {
        name         = "headers-inspect",
        upstream_url = helpers.mock_upstream_url,
        hosts        = {
          "headers-inspect.com",
        },
      },
      {
        name          = "preserved",
        upstream_url  = helpers.mock_upstream_url,
        hosts         = {
          "preserved.com",
        },
        preserve_host = true,
      },
    }

    assert(helpers.start_kong(config))
  end
end

local stop_kong = helpers.stop_kong

local function request_headers(headers)
  local res = assert(client:send {
    method  = "GET",
    path    = "/",
    headers = headers,
  })

  local json = assert.res_status(200, res)

  return cjson.decode(json).headers
end


describe("Upstream header(s)", function()

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  describe("(using the default configuration values)", function()

    lazy_setup(start_kong {
        nginx_conf       = "spec/fixtures/custom_nginx.template",
        lua_package_path = "?/init.lua;./kong/?.lua;./spec-old-api/fixtures/?.lua",
    })

    lazy_teardown(stop_kong)

    describe("X-Real-IP", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]      = "headers-inspect.com",
          ["X-Real-IP"] = "10.0.0.1",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
      end)
    end)

    describe("X-Forwarded-For", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("127.0.0.1", headers["x-forwarded-for"])
      end)

      it("should be appended if present in request", function()
        local headers = request_headers {
          ["Host"]            = "headers-inspect.com",
          ["X-Forwarded-For"] = "10.0.0.1",
        }

        assert.equal("10.0.0.1, 127.0.0.1", headers["x-forwarded-for"])
      end)
    end)

    describe("X-Forwarded-Proto", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("http", headers["x-forwarded-proto"])
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]              = "headers-inspect.com",
          ["X-Forwarded-Proto"] = "https",
        }

        assert.equal("http", headers["x-forwarded-proto"])
      end)
    end)

    describe("X-Forwarded-Host", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("headers-inspect.com", headers["x-forwarded-host"])
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]             = "headers-inspect.com",
          ["X-Forwarded-Host"] = "example.com",
        }

        assert.equal("headers-inspect.com", headers["x-forwarded-host"])
      end)
    end)

    describe("X-Forwarded-Port", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]             = "headers-inspect.com",
          ["X-Forwarded-Port"] = "80",
        }

        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
      end)
    end)

    describe("with the downstream host preserved", function()
      it("should be added if not present in request while preserving the downstream host", function()
        local headers = request_headers {
          ["Host"] = "preserved.com",
        }

        assert.equal("preserved.com", headers["host"])
        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1", headers["x-forwarded-for"])
        assert.equal("http", headers["x-forwarded-proto"])
        assert.equal("preserved.com", headers["x-forwarded-host"])
        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
      end)

      it("should be added if present in request while preserving the downstream host", function()
        local headers = request_headers {
          ["Host"]              = "preserved.com",
          ["X-Real-IP"]         = "10.0.0.1",
          ["X-Forwarded-For"]   = "10.0.0.1",
          ["X-Forwarded-Proto"] = "https",
          ["X-Forwarded-Host"]  = "example.com",
          ["X-Forwarded-Port"]  = "80",
        }

        assert.equal("preserved.com", headers["host"])
        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("10.0.0.1, 127.0.0.1", headers["x-forwarded-for"])
        assert.equal("http", headers["x-forwarded-proto"])
        assert.equal("preserved.com", headers["x-forwarded-host"])
        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
      end)
    end)

    describe("with the downstream host discarded", function()
      it("should be added if not present in request while discarding the downstream host", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal(helpers.mock_upstream_host .. ":" ..
                     helpers.mock_upstream_port,
                     headers["host"])
        assert.equal(helpers.mock_upstream_host, headers["x-real-ip"])
        assert.equal(helpers.mock_upstream_host, headers["x-forwarded-for"])
        assert.equal("http", headers["x-forwarded-proto"])
        assert.equal("headers-inspect.com", headers["x-forwarded-host"])
        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
      end)

      it("if present in request while discarding the downstream host", function()
        local headers = request_headers {
          ["Host"]              = "headers-inspect.com",
          ["X-Real-IP"]         = "10.0.0.1",
          ["X-Forwarded-For"]   = "10.0.0.1",
          ["X-Forwarded-Proto"] = "https",
          ["X-Forwarded-Host"]  = "example.com",
          ["X-Forwarded-Port"]  = "80",
        }

        assert.equal(helpers.mock_upstream_host .. ":" ..
                     helpers.mock_upstream_port,
                     headers["host"])
        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("10.0.0.1, 127.0.0.1", headers["x-forwarded-for"])
        assert.equal("http", headers["x-forwarded-proto"])
        assert.equal("headers-inspect.com", headers["x-forwarded-host"])
        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
      end)
    end)

  end)

  describe("(using the trusted configuration values)", function()

    lazy_setup(start_kong {
        trusted_ips      = "127.0.0.1",
        nginx_conf       = "spec/fixtures/custom_nginx.template",
        lua_package_path = "?/init.lua;./kong/?.lua;./spec-old-api/fixtures/?.lua",
    })

    lazy_teardown(stop_kong)

    describe("X-Real-IP", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
      end)

      it("should be forwarded if present in request", function()
        local headers = request_headers {
          ["Host"]      = "headers-inspect.com",
          ["X-Real-IP"] = "10.0.0.1",
        }

        assert.equal("10.0.0.1", headers["x-real-ip"])
      end)
    end)

    describe("X-Forwarded-For", function()

      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("127.0.0.1", headers["x-forwarded-for"])
      end)

      it("should be appended if present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
          ["X-Forwarded-For"] = "10.0.0.1",
        }

        assert.equal("10.0.0.1, 127.0.0.1", headers["x-forwarded-for"])
      end)

    end)

    describe("X-Forwarded-Proto", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("http", headers["x-forwarded-proto"])
      end)

      it("should be forwarded if present in request", function()
        local headers = request_headers {
          ["Host"]              = "headers-inspect.com",
          ["X-Forwarded-Proto"] = "https",
        }

        assert.equal("https", headers["x-forwarded-proto"])
      end)
    end)

    describe("X-Forwarded-Host", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("headers-inspect.com", headers["x-forwarded-host"])
      end)

      it("should be forwarded if present in request", function()
        local headers = request_headers {
          ["Host"]             = "headers-inspect.com",
          ["X-Forwarded-Host"] = "example.com",
        }

        assert.equal("example.com", headers["x-forwarded-host"])
      end)
    end)

    describe("X-Forwarded-Port", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
      end)

      it("should be forwarded if present in request", function()
        local headers = request_headers {
          ["Host"]             = "headers-inspect.com",
          ["X-Forwarded-Port"] = "80",
        }

        assert.equal("80", headers["x-forwarded-port"])
      end)

    end)

  end)

  describe("(using the non-trusted configuration values)", function()

    lazy_setup(start_kong {
        trusted_ips      = "10.0.0.1",
        nginx_conf       = "spec/fixtures/custom_nginx.template",
        lua_package_path = "?/init.lua;./kong/?.lua;./spec-old-api/fixtures/?.lua",
    })

    lazy_teardown(stop_kong)

    describe("X-Real-IP", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]      = "headers-inspect.com",
          ["X-Real-IP"] = "10.0.0.1",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
      end)
    end)

    describe("X-Forwarded-For", function()

      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("127.0.0.1", headers["x-forwarded-for"])
      end)

      it("should be appended if present in request", function()
        local headers = request_headers {
          ["Host"]            = "headers-inspect.com",
          ["X-Forwarded-For"] = "10.0.0.1",
        }

        assert.equal("10.0.0.1, 127.0.0.1", headers["x-forwarded-for"])
      end)

    end)

    describe("X-Forwarded-Proto", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("http", headers["x-forwarded-proto"])
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]              = "headers-inspect.com",
          ["X-Forwarded-Proto"] = "https",
        }

        assert.equal("http", headers["x-forwarded-proto"])
      end)
    end)

    describe("X-Forwarded-Host", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("headers-inspect.com", headers["x-forwarded-host"])
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]             = "headers-inspect.com",
          ["X-Forwarded-Host"] = "example.com",
        }

        assert.equal("headers-inspect.com", headers["x-forwarded-host"])
      end)
    end)

    describe("X-Forwarded-Port", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]             = "headers-inspect.com",
          ["X-Forwarded-Port"] = "80",
        }

        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
      end)
    end)
  end)

  describe("(using the recursive trusted configuration values)", function()

    lazy_setup(start_kong {
        real_ip_header    = "X-Forwarded-For",
        real_ip_recursive = "on",
        trusted_ips       = "127.0.0.1,172.16.0.1,192.168.0.1",
        nginx_conf        = "spec/fixtures/custom_nginx.template",
        lua_package_path  = "?/init.lua;./kong/?.lua;./spec-old-api/fixtures/?.lua",
    })

    lazy_teardown(stop_kong)

    describe("X-Real-IP and X-Forwarded-For", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1", headers["x-forwarded-for"])
      end)

      it("should be changed according to rules if present in request", function()
        local headers = request_headers {
          ["Host"]            = "headers-inspect.com",
          ["X-Forwarded-For"] = "127.0.0.1, 10.0.0.1, 192.168.0.1, 127.0.0.1, 172.16.0.1",
          ["X-Real-IP"]       = "10.0.0.2",
        }

        assert.equal("10.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1, 10.0.0.1, 192.168.0.1, 127.0.0.1, 172.16.0.1, 127.0.0.1", headers["x-forwarded-for"])
      end)
    end)

    describe("X-Forwarded-Port", function()
      it("should be forwarded even if X-Forwarded-For header has a port in it", function()
        local headers = request_headers {
          ["Host"]             = "headers-inspect.com",
          ["X-Forwarded-For"]  = "127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18",
          ["X-Real-IP"]        = "10.0.0.2",
          ["X-Forwarded-Port"] = "14",
        }

        assert.equal("10.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18, 127.0.0.1", headers["x-forwarded-for"])
        assert.equal(14, tonumber(headers["x-forwarded-port"]))
      end)

      pending("should take a port from X-Forwarded-For header if it has a port in it", function()
--        local headers = request_headers {
--          ["Host"]             = "headers-inspect.com",
--          ["X-Forwarded-For"]  = "127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18",
--          ["X-Real-IP"]        = "10.0.0.2",
--        }
--
--        assert.equal("10.0.0.1", headers["x-real-ip"])
--        assert.equal("127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18, 127.0.0.1", headers["x-forwarded-for"])
--        assert.equal(16, tonumber(headers["x-forwarded-port"]))
      end)
    end)
  end)

  describe("(using the recursive non-trusted configuration values)", function()
    lazy_setup(start_kong {
        real_ip_header    = "X-Forwarded-For",
        real_ip_recursive = "on",
        trusted_ips       = "10.0.0.1,172.16.0.1,192.168.0.1",
        nginx_conf        = "spec/fixtures/custom_nginx.template",
        lua_package_path  = "?/init.lua;./kong/?.lua;./spec-old-api/fixtures/?.lua",
    })

    lazy_teardown(stop_kong)

    describe("X-Real-IP and X-Forwarded-For", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "headers-inspect.com",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1", headers["x-forwarded-for"])
      end)

      it("should be changed according to rules if present in request", function()
        local headers = request_headers {
          ["Host"]            = "headers-inspect.com",
          ["X-Forwarded-For"] = "10.0.0.1, 127.0.0.2, 10.0.0.1, 192.168.0.1, 172.16.0.1",
          ["X-Real-IP"]       = "10.0.0.2",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("10.0.0.1, 127.0.0.2, 10.0.0.1, 192.168.0.1, 172.16.0.1, 127.0.0.1", headers["x-forwarded-for"])
      end)
    end)

    describe("X-Forwarded-Port", function()
      it("should be replaced even if X-Forwarded-Port and X-Forwarded-For headers have a port in it", function()
        local headers = request_headers {
          ["Host"]             = "headers-inspect.com",
          ["X-Forwarded-For"]  = "127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18",
          ["X-Real-IP"]        = "10.0.0.2",
          ["X-Forwarded-Port"] = "14",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18, 127.0.0.1", headers["x-forwarded-for"])
        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
      end)

      it("should not take a port from X-Forwarded-For header if it has a port in it", function()
        local headers = request_headers {
          ["Host"]             = "headers-inspect.com",
          ["X-Forwarded-For"]  = "127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18",
          ["X-Real-IP"]        = "10.0.0.2",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18, 127.0.0.1", headers["x-forwarded-for"])
        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
      end)
    end)

  end)

  describe("(using trusted proxy protocol configuration values)", function()
    local proxy_ip = helpers.get_proxy_ip(false)
    local proxy_port = helpers.get_proxy_port(false)

    lazy_setup(start_kong {
      proxy_listen      = proxy_ip .. ":" .. proxy_port .. " proxy_protocol",
      real_ip_header    = "proxy_protocol",
      real_ip_recursive = "on",
      trusted_ips       = "127.0.0.1,172.16.0.1,192.168.0.1",
      nginx_conf        = "spec/fixtures/custom_nginx.template",
      lua_package_path  = "?/init.lua;./kong/?.lua;./spec-old-api/fixtures/?.lua",
    })

    lazy_teardown(stop_kong)

    describe("X-Real-IP, X-Forwarded-For and X-Forwarded-Port", function()
      it("should be added if not present in request", function()
        local sock = ngx.socket.tcp()
        local request = "PROXY TCP4 192.168.0.1 " .. helpers.get_proxy_ip(false) .. " 56324 " .. helpers.get_proxy_port(false) .. "\r\n" ..
                        "GET / HTTP/1.1\r\n" ..
                        "Host: headers-inspect.com\r\n" ..
                        "Connection: close\r\n" ..
                        "\r\n"

        assert(sock:connect(helpers.get_proxy_ip(false), helpers.get_proxy_port(false)))
        assert(sock:send(request))

        local response, err = sock:receive "*a"

        assert(response, err)

        local json = string.match(response, "%b{}")

        assert.is_not_nil(json)

        local headers = cjson.decode(json).headers

        assert.equal("192.168.0.1", headers["x-real-ip"])
        assert.equal("192.168.0.1", headers["x-forwarded-for"])
        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
        assert(sock:close())
      end)

      it("should be changed according to rules if present in request", function()
        local sock = ngx.socket.tcp()
        local request = "PROXY TCP4 192.168.0.1 " .. helpers.get_proxy_ip(false) .. " 56324 " .. helpers.get_proxy_port(false) .. "\r\n" ..
                        "GET / HTTP/1.1\r\n" ..
                        "Host: headers-inspect.com\r\n" ..
                        "Connection: close\r\n" ..
                        "X-Real-IP: 10.0.0.2\r\n" ..
                        "X-Forwarded-For: 10.0.0.1, 127.0.0.2, 10.0.0.1, 192.168.0.1, 172.16.0.1\r\n" ..
                        "\r\n"

        assert(sock:connect(helpers.get_proxy_ip(false), helpers.get_proxy_port(false)))
        assert(sock:send(request))

        local response, err = sock:receive "*a"

        assert(response, err)

        local json = string.match(response, "%b{}")

        assert.is_not_nil(json)

        local headers = cjson.decode(json).headers

        assert.equal("192.168.0.1", headers["x-real-ip"])
        assert.equal("10.0.0.1, 127.0.0.2, 10.0.0.1, 192.168.0.1, 172.16.0.1, 127.0.0.1", headers["x-forwarded-for"])
        assert(sock:close())
      end)
    end)

    describe("X-Forwarded-Port", function()
      it("should be forwarded even if proxy protocol and X-Forwarded-For header has a port in it", function()
        local sock = ngx.socket.tcp()
        local request = "PROXY TCP4 192.168.0.1 " .. helpers.get_proxy_ip(false) .. " 56324 " .. helpers.get_proxy_port(false) .. "\r\n" ..
                        "GET / HTTP/1.1\r\n" ..
                        "Host: headers-inspect.com\r\n" ..
                        "Connection: close\r\n" ..
                        "X-Real-IP: 10.0.0.2\r\n" ..
                        "X-Forwarded-For: 127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18\r\n" ..
                        "X-Forwarded-Port: 14\r\n" ..
                        "\r\n"

        assert(sock:connect(helpers.get_proxy_ip(false), helpers.get_proxy_port(false)))
        assert(sock:send(request))

        local response, err = sock:receive "*a"

        assert(response, err)

        local json = string.match(response, "%b{}")

        assert.is_not_nil(json)

        local headers = cjson.decode(json).headers

        assert.equal("192.168.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18, 127.0.0.1", headers["x-forwarded-for"])
        assert.equal(14, tonumber(headers["x-forwarded-port"]))
        assert(sock:close())
      end)
    end)
  end)

  describe("(using non-trusted proxy protocol configuration values)", function()
    local proxy_ip = helpers.get_proxy_ip(false)
    local proxy_port = helpers.get_proxy_port(false)

    lazy_setup(start_kong {
      proxy_listen      = proxy_ip .. ":" .. proxy_port .. " proxy_protocol",
      real_ip_header    = "proxy_protocol",
      real_ip_recursive = "on",
      trusted_ips       = "10.0.0.1,172.16.0.1,192.168.0.1",
      nginx_conf        = "spec/fixtures/custom_nginx.template",
      lua_package_path  = "?/init.lua;./kong/?.lua;./spec-old-api/fixtures/?.lua",
    })

    lazy_teardown(stop_kong)

    describe("X-Real-IP, X-Forwarded-For and X-Forwarded-Port", function()
      it("should be added if not present in request", function()
        local sock = ngx.socket.tcp()
        local request = "PROXY TCP4 192.168.0.1 " .. helpers.get_proxy_ip(false) .. " 56324 " .. helpers.get_proxy_port(false) .. "\r\n" ..
                        "GET / HTTP/1.1\r\n" ..
                        "Host: headers-inspect.com\r\n" ..
                        "Connection: close\r\n" ..
                        "\r\n"

        assert(sock:connect(helpers.get_proxy_ip(false), helpers.get_proxy_port(false)))
        assert(sock:send(request))

        local response, err = sock:receive "*a"

        assert(response, err)

        local json = string.match(response, "%b{}")

        assert.is_not_nil(json)

        local headers = cjson.decode(json).headers

        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1", headers["x-forwarded-for"])
        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
        assert(sock:close())
      end)

      it("should be changed according to rules if present in request", function()
        local sock = ngx.socket.tcp()
        local request = "PROXY TCP4 192.168.0.1 " .. helpers.get_proxy_ip(false) .. " 56324 " .. helpers.get_proxy_port(false) .. "\r\n" ..
                        "GET / HTTP/1.1\r\n" ..
                        "Host: headers-inspect.com\r\n" ..
                        "Connection: close\r\n" ..
                        "X-Real-IP: 10.0.0.2\r\n" ..
                        "X-Forwarded-For: 10.0.0.1, 127.0.0.2, 10.0.0.1, 192.168.0.1, 172.16.0.1\r\n" ..
                        "\r\n"

        assert(sock:connect(helpers.get_proxy_ip(false), helpers.get_proxy_port(false)))
        assert(sock:send(request))

        local response, err = sock:receive "*a"

        assert(response, err)

        local json = string.match(response, "%b{}")

        assert.is_not_nil(json)

        local headers = cjson.decode(json).headers

        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("10.0.0.1, 127.0.0.2, 10.0.0.1, 192.168.0.1, 172.16.0.1, 127.0.0.1", headers["x-forwarded-for"])
        assert(sock:close())
      end)
    end)

    describe("X-Forwarded-Port", function()
      it("should be replaced even if proxy protocol, X-Forwarded-Port and X-Forwarded-For headers have a port in it", function()
        local sock = ngx.socket.tcp()
        local request = "PROXY TCP4 192.168.0.1 " .. helpers.get_proxy_ip(false) .. " 56324 " .. helpers.get_proxy_port(false) .. "\r\n" ..
                        "GET / HTTP/1.1\r\n" ..
                        "Host: headers-inspect.com\r\n" ..
                        "Connection: close\r\n" ..
                        "X-Real-IP: 10.0.0.2\r\n" ..
                        "X-Forwarded-For: 127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18\r\n" ..
                        "X-Forwarded-Port: 14\r\n" ..
                        "\r\n"

        assert(sock:connect(helpers.get_proxy_ip(false), helpers.get_proxy_port(false)))
        assert(sock:send(request))

        local response, err = sock:receive "*a"

        assert(response, err)

        local json = string.match(response, "%b{}")

        assert.is_not_nil(json)

        local headers = cjson.decode(json).headers

        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18, 127.0.0.1", headers["x-forwarded-for"])
        assert.equal(helpers.get_proxy_port(false), tonumber(headers["x-forwarded-port"]))
        assert(sock:close())
      end)
    end)
  end)

end)
