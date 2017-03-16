local helpers = require "spec.helpers"
local cjson = require "cjson"
local client

local function insert_apis(arr)
  if type(arr) ~= "table" then
    return error("expected arg #1 to be a table", 2)
  end

  helpers.dao:truncate_tables()

  for i = 1, #arr do
    assert(helpers.dao.apis:insert(arr[i]))
  end
end

local function start_kong(config)

  insert_apis {
    {
      name          = "headers-inspect",
      uris          = "/headers-inspect",
      upstream_url  = "http://placeholder.com", -- unused
    },
    --[[
    {
      name          = "preserved",
      hosts         = "preserved.com",
      preserve_host = true,
      upstream_url  = "http://" .. helpers.test_conf.proxy_listen .. "/headers-inspect",
    },
    --]]
    {
      name          = "proxy-mock",
      hosts         = "proxy-mock.com",
      upstream_url  = "http://" .. helpers.test_conf.proxy_listen .. "/headers-inspect",
    }
  }

  assert(helpers.start_kong(config))

  local admin_client = helpers.admin_client()

  local res = assert(admin_client:send {
    method = "POST",
    path   = "/apis/headers-inspect/plugins",
    body   = {
      name = "headers-inspect",
    },
    headers = {
      ["Content-Type"] = "application/json",
    }
  })

  assert.res_status(201, res)

  admin_client:close()
end

local stop_kong = helpers.stop_kong

local function request_headers(headers)
  local res = assert(client:send {
    method  = "GET",
    path    = "/",
    headers = headers,
  })

  local headers_json = assert.res_status(200, res)

  return cjson.decode(headers_json)
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

    setup(function()
      start_kong {
        custom_plugins   = "headers-inspect",
        lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua",
      }
    end)

    teardown(stop_kong)

    describe("X-Real-IP", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]      = "proxy-mock.com",
          ["X-Real-IP"] = "10.0.0.1",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
      end)
    end)

    describe("X-Forwarded-For", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("127.0.0.1", headers["x-forwarded-for"])
      end)

      it("should be appended if present in request", function()
        local headers = request_headers {
          ["Host"]            = "proxy-mock.com",
          ["X-Forwarded-For"] = "10.0.0.1",
        }

        assert.equal("10.0.0.1, 127.0.0.1", headers["x-forwarded-for"])
      end)
    end)

    describe("X-Forwarded-Proto", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("http", headers["x-forwarded-proto"])
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]              = "proxy-mock.com",
          ["X-Forwarded-Proto"] = "https",
        }

        assert.equal("http", headers["x-forwarded-proto"])
      end)
    end)

    describe("X-Forwarded-Host", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("proxy-mock.com", headers["x-forwarded-host"])
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]             = "proxy-mock.com",
          ["X-Forwarded-Host"] = "example.com",
        }

        assert.equal("proxy-mock.com", headers["x-forwarded-host"])
      end)
    end)

    describe("X-Forwarded-Port", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal(helpers.test_conf.proxy_port, tonumber(headers["x-forwarded-port"]))
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]             = "proxy-mock.com",
          ["X-Forwarded-Port"] = "80",
        }

        assert.equal(helpers.test_conf.proxy_port, tonumber(headers["x-forwarded-port"]))
      end)
    end)

    pending("with the downstream host preserved", function()
--      it("should be added if not present in request while preserving the downstream host", function()
--        local headers = request_headers {
--          ["Host"] = "preserved.com",
--        }
--
--        assert.equal("preserved.com", headers["host"])
--        assert.equal("127.0.0.1", headers["x-real-ip"])
--        assert.equal("127.0.0.1", headers["x-forwarded-for"])
--        assert.equal("http", headers["x-forwarded-proto"])
--        assert.equal("preserved.com", headers["x-forwarded-host"])
--        assert.equal(helpers.test_conf.proxy_port, tonumber(headers["x-forwarded-port"]))
--      end)
--
--      it("should be added if present in request while preserving the downstream host", function()
--        local headers = request_headers {
--          ["Host"]              = "preserved.com",
--          ["X-Real-IP"]         = "10.0.0.1",
--          ["X-Forwarded-For"]   = "10.0.0.1",
--          ["X-Forwarded-Proto"] = "https",
--          ["X-Forwarded-Host"]  = "example.com",
--          ["X-Forwarded-Port"]  = "80",
--        }
--
--        assert.equal("preserved.com", headers["host"])
--        assert.equal("127.0.0.1", headers["x-real-ip"])
--        assert.equal("10.0.0.1, 127.0.0.1", headers["x-forwarded-for"])
--        assert.equal("http", headers["x-forwarded-proto"])
--        assert.equal("preserved.com", headers["x-forwarded-host"])
--        assert.equal(helpers.test_conf.proxy_port, tonumber(headers["x-forwarded-port"]))
--      end)
    end)

    describe("with the downstream host discarded", function()
      it("should be added if not present in request while discarding the downstream host", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal(helpers.test_conf.proxy_listen, headers["host"])
        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1", headers["x-forwarded-for"])
        assert.equal("http", headers["x-forwarded-proto"])
        assert.equal("proxy-mock.com", headers["x-forwarded-host"])
        assert.equal(helpers.test_conf.proxy_port, tonumber(headers["x-forwarded-port"]))
      end)

      it("if present in request while discarding the downstream host", function()
        local headers = request_headers {
          ["Host"]              = "proxy-mock.com",
          ["X-Real-IP"]         = "10.0.0.1",
          ["X-Forwarded-For"]   = "10.0.0.1",
          ["X-Forwarded-Proto"] = "https",
          ["X-Forwarded-Host"]  = "example.com",
          ["X-Forwarded-Port"]  = "80",
        }

        assert.equal(helpers.test_conf.proxy_listen, headers["host"])
        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("10.0.0.1, 127.0.0.1", headers["x-forwarded-for"])
        assert.equal("http", headers["x-forwarded-proto"])
        assert.equal("proxy-mock.com", headers["x-forwarded-host"])
        assert.equal(helpers.test_conf.proxy_port, tonumber(headers["x-forwarded-port"]))
      end)
    end)

  end)

  describe("(using the trusted configuration values)", function()

    setup(function()
      start_kong {
        trusted_ips = "127.0.0.1",
        custom_plugins = "headers-inspect",
        lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua",
      }
    end)

    teardown(stop_kong)

    describe("X-Real-IP", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
      end)

      it("should be forwarded if present in request", function()
        local headers = request_headers {
          ["Host"]      = "proxy-mock.com",
          ["X-Real-IP"] = "10.0.0.1",
        }

        assert.equal("10.0.0.1", headers["x-real-ip"])
      end)
    end)

    describe("X-Forwarded-For", function()

      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("127.0.0.1", headers["x-forwarded-for"])
      end)

      it("should be appended if present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
          ["X-Forwarded-For"] = "10.0.0.1",
        }

        assert.equal("10.0.0.1, 127.0.0.1", headers["x-forwarded-for"])
      end)

    end)

    describe("X-Forwarded-Proto", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("http", headers["x-forwarded-proto"])
      end)

      it("should be forwarded if present in request", function()
        local headers = request_headers {
          ["Host"]              = "proxy-mock.com",
          ["X-Forwarded-Proto"] = "https",
        }

        assert.equal("https", headers["x-forwarded-proto"])
      end)
    end)

    describe("X-Forwarded-Host", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("proxy-mock.com", headers["x-forwarded-host"])
      end)

      it("should be forwarded if present in request", function()
        local headers = request_headers {
          ["Host"]             = "proxy-mock.com",
          ["X-Forwarded-Host"] = "example.com",
        }

        assert.equal("example.com", headers["x-forwarded-host"])
      end)
    end)

    describe("X-Forwarded-Port", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal(helpers.test_conf.proxy_port, tonumber(headers["x-forwarded-port"]))
      end)

      it("should be forwarded if present in request", function()
        local headers = request_headers {
          ["Host"]             = "proxy-mock.com",
          ["X-Forwarded-Port"] = "80",
        }

        assert.equal("80", headers["x-forwarded-port"])
      end)

    end)

  end)

  describe("(using the non-trusted configuration values)", function()

    setup(function()
      start_kong {
        trusted_ips      = "10.0.0.1",
        custom_plugins   = "headers-inspect",
        lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua",
      }
    end)

    teardown(stop_kong)

    describe("X-Real-IP", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]      = "proxy-mock.com",
          ["X-Real-IP"] = "10.0.0.1",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
      end)
    end)

    describe("X-Forwarded-For", function()

      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("127.0.0.1", headers["x-forwarded-for"])
      end)

      it("should be appended if present in request", function()
        local headers = request_headers {
          ["Host"]            = "proxy-mock.com",
          ["X-Forwarded-For"] = "10.0.0.1",
        }

        assert.equal("10.0.0.1, 127.0.0.1", headers["x-forwarded-for"])
      end)

    end)

    describe("X-Forwarded-Proto", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("http", headers["x-forwarded-proto"])
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]              = "proxy-mock.com",
          ["X-Forwarded-Proto"] = "https",
        }

        assert.equal("http", headers["x-forwarded-proto"])
      end)
    end)

    describe("X-Forwarded-Host", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("proxy-mock.com", headers["x-forwarded-host"])
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]             = "proxy-mock.com",
          ["X-Forwarded-Host"] = "example.com",
        }

        assert.equal("proxy-mock.com", headers["x-forwarded-host"])
      end)
    end)

    describe("X-Forwarded-Port", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal(helpers.test_conf.proxy_port, tonumber(headers["x-forwarded-port"]))
      end)

      it("should be replaced if present in request", function()
        local headers = request_headers {
          ["Host"]             = "proxy-mock.com",
          ["X-Forwarded-Port"] = "80",
        }

        assert.equal(helpers.test_conf.proxy_port, tonumber(headers["x-forwarded-port"]))
      end)
    end)
  end)

  describe("(using the recursive trusted configuration values)", function()

    setup(function()
      start_kong {
        real_ip_header    = "X-Forwarded-For",
        real_ip_recursive = "on",
        trusted_ips       = "127.0.0.1,172.16.0.1,192.168.0.1",
        custom_plugins    = "headers-inspect",
        lua_package_path  = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua",
      }
    end)

    teardown(stop_kong)

    describe("X-Real-IP and X-Forwarded-For", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1", headers["x-forwarded-for"])
      end)

      it("should be changed according to rules if present in request", function()
        local headers = request_headers {
          ["Host"]            = "proxy-mock.com",
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
          ["Host"]             = "proxy-mock.com",
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
--          ["Host"]             = "proxy-mock.com",
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

  describe("(using the recursice non-trusted configuration values)", function()
    setup(function()
      start_kong {
        real_ip_header    = "X-Forwarded-For",
        real_ip_recursive = "on",
        trusted_ips       = "10.0.0.1,172.16.0.1,192.168.0.1",
        custom_plugins    = "headers-inspect",
        lua_package_path  = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua",
      }
    end)

    teardown(stop_kong)

    describe("X-Real-IP and X-Forwarded-For", function()
      it("should be added if not present in request", function()
        local headers = request_headers {
          ["Host"] = "proxy-mock.com",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1", headers["x-forwarded-for"])
      end)

      it("should be changed according to rules if present in request", function()
        local headers = request_headers {
          ["Host"]            = "proxy-mock.com",
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
          ["Host"]             = "proxy-mock.com",
          ["X-Forwarded-For"]  = "127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18",
          ["X-Real-IP"]        = "10.0.0.2",
          ["X-Forwarded-Port"] = "14",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18, 127.0.0.1", headers["x-forwarded-for"])
        assert.equal(helpers.test_conf.proxy_port, tonumber(headers["x-forwarded-port"]))
      end)

      it("should not take a port from X-Forwarded-For header if it has a port in it", function()
        local headers = request_headers {
          ["Host"]             = "proxy-mock.com",
          ["X-Forwarded-For"]  = "127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18",
          ["X-Real-IP"]        = "10.0.0.2",
        }

        assert.equal("127.0.0.1", headers["x-real-ip"])
        assert.equal("127.0.0.1:14, 10.0.0.1:15, 192.168.0.1:16, 127.0.0.1:17, 172.16.0.1:18, 127.0.0.1", headers["x-forwarded-for"])
        assert.equal(helpers.test_conf.proxy_port, tonumber(headers["x-forwarded-port"]))
      end)
    end)

  end)
end)
