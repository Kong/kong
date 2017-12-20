local helpers = require "spec.helpers"
local math_fmod = math.fmod
local crc32 = ngx.crc32_short
local uuid = require("kong.tools.utils").uuid

-- mocked upstream host
local function http_server(timeout, count, port, ...)
  local threads = require "llthreads2.ex"
  local thread = threads.new({
    function(timeout, count, port)
      local socket = require "socket"
      local server = assert(socket.tcp())
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("*", port))
      assert(server:listen())

      local expire = socket.gettime() + timeout
      assert(server:settimeout(timeout))

      local success = 0
      while count > 0 do
        local client, err
        client, err = server:accept()
        if err == "timeout" then
          if socket.gettime() > expire then
            server:close()
            error("timeout")
          end
        elseif not client then
          server:close()
          error(err)
        else
          count = count - 1

          local err
          local line_count = 0
          while line_count < 7 do
            _, err = client:receive()
            if err then
              break
            else
              line_count = line_count + 1
            end
          end

          if err then
            client:close()
            server:close()
            error(err)
          end
          local response_json = '{"vars": {"request_uri": "/requests/path2"}}'
          local s = client:send(
            'HTTP/1.1 200 OK\r\n' ..
                    'Connection: close\r\n' ..
                    'Content-Length: '.. #response_json .. '\r\n' ..
                    '\r\n' ..
                    response_json
          )

          client:close()
          if s then
            success = success + 1
          end
        end
      end

      server:close()
      return success
    end
  }, timeout, count, port)

  local server = thread:start(...)
  ngx.sleep(0.2)
  return server
end


-- Generates consumers and key-auth keys.
-- Calls the management api to create the consumers and key-auth credentials
-- @param admin_client the client to use to create the consumers and key-auth credentials
-- @param list a list/array of integers
-- @return a table index by the integer from the list, with as value a uuid,
-- the uuid will be the consumer uuid, for which the hash, with the given `modulo`
-- returns the integer value.
-- Example:
-- call with `list = { 0, 2, 7, 8 }` and `modulo = 10` returns:
-- {
--   [1] = "some uuid", -- where: fmod(crc32(uuid), 10) == 0
--   [2] = "some uuid", -- where: fmod(crc32(uuid), 10) == 2
--   [7] = "some uuid", -- where: fmod(crc32(uuid), 10) == 7
--   [8] = "some uuid", -- where: fmod(crc32(uuid), 10) == 8
-- }
local function generate_consumers(admin_client, list, modulo)
  local result = {}
  -- generate the matching uuids
  for _, int in ipairs(list) do
    assert(int < modulo, "entries must be smaller than provided modulo")
    local id
    repeat
      id = uuid()
    until math_fmod(crc32(id), modulo) == int
    result[int] = id
  end
  -- create consumers and their key-auth keys
  for _, id in pairs(result) do
    local res = assert(admin_client:send {
      method = "POST",
      path = "/consumers",
      headers = {
        ["Content-Type"] = "application/json"
      },
      body = {
        id = id,
        username = id,
      }
    })
    assert.response(res).has.status(201)
    res = assert(admin_client:send {
      method = "POST",
      path = "/consumers/" .. id .. "/key-auth",
      headers = {
        ["Content-Type"] = "application/json"
      },
      body = {
        key = id,
      }
    })
    assert.response(res).has.status(201)
  end
  return result
end

describe("Plugin: canary (access)", function()
  local proxy_client, admin_client, api1, api2

  setup(function()
    helpers.run_migrations()

    api1 = assert(helpers.dao.apis:insert {
      name         = "api-1",
      hosts        = { "canary1.com" },
      upstream_url = helpers.mock_upstream_url,
    })

    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api1.id,
      config = {}
    })

    api2 = assert(helpers.dao.apis:insert {
      name         = "api-2",
      hosts        = { "canary2.com" },
      upstream_url = helpers.mock_upstream_url,
    })

    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api2.id,
      config = {}
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
      custom_plugins = "canary",
    }))
    proxy_client = helpers.proxy_client()
    admin_client = helpers.admin_client()
  end)


  teardown(function()
    if proxy_client then
      proxy_client:close()
    end
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong(nil, true)
  end)

  local test_plugin_id -- retain id to remove again in after_each, max 1 per test
  -- add a canary plugin to an api, with the given config.
  -- in `after_each` handler it will be auto-removed
  local function add_canary(api_id, config)
    local res = assert(admin_client:send {
      method = "POST",
      path = "/apis/" .. api_id .."/plugins",
      headers = {
        ["Content-Type"] = "application/json"
      },
      body = {
        name = "canary",
        config = config,
      }
    })
    assert.response(res).has.status(201)
    local json = assert.response(res).has.jsonbody()
    test_plugin_id = json.id
  end

  after_each(function()
    -- when a test plugin was added, we remove it again to clean up
    if test_plugin_id then
      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/plugins/" .. test_plugin_id,
      })
      assert.response(res).has.status(204)
    end
    test_plugin_id = nil
  end)


  describe("Canary", function()

    it("test percentage 50%", function()
      add_canary(api1.id, {
        upstream_uri = "/requests/path2",
        percentage = "50",
        steps = "4",
      })
      local ids = generate_consumers(admin_client, {0,1,2,3}, 4)
      local count = {}
      for _, apikey in pairs(ids) do
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary1.com",
            ["apikey"] = apikey
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
      end

      assert.is_equal(count["/requests/path2"],
        count["/requests"] )
    end)

    it("test percentage 50% with upstream_host", function()
      local server1 = http_server(10, 2, 20002)
      add_canary(api1.id, {
        upstream_host = "127.0.0.1:20002",
        percentage = "50",
        steps = "4",
      })
      local ids = generate_consumers(admin_client, {0,1,2,3}, 4)
      local count = {}
      for _, apikey in pairs(ids) do
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary1.com",
            ["apikey"] = apikey
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
      end

      assert.is_equal(count["/requests/path2"], count["/requests"])

      local _, success = server1:join()
      assert.is_equal(2, success)
    end)

    it("test 'none' as hash", function()
      add_canary(api1.id, {
        upstream_uri = "/requests/path2",
        percentage = "50",
        steps = "4",
        hash = "none",
      })
      -- only use 1 consumer, which should still randomly end up in all targets
      local apikey = generate_consumers(admin_client, {0}, 4)[0]
      local count = {
        ["/requests/path2"] = 0,
        ["/requests"] = 0,
      }
      local timeout = ngx.now() + 30
      while count["/requests/path2"] == 0 or
              count["/requests"] == 0 do
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary1.com",
            ["apikey"] = apikey
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        count[json.vars.request_uri] = count[json.vars.request_uri] + 1
        assert(ngx.now() < timeout, "timeout")
      end
    end)

    it("test 'ip' as hash", function()
      add_canary(api1.id, {
        upstream_uri = "/requests/path2",
        percentage = "50",
        steps = "4",
        hash = "ip",
      })
      local ids = generate_consumers(admin_client, {0,1,2,3}, 4)
      local count = {}
      for _, apikey in pairs(ids) do
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary1.com",
            ["apikey"] = apikey
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
      end
      -- we have 4 consumers, but they should, based on ip, be all in the same target
      if count["/requests/path2"] then
        assert.are.equal(4, count["/requests/path2"])
        assert.is_nil(count["/requests"])
      else
        assert.are.equal(4, count["/requests"])
        assert.is_nil(count["/requests/path2"])
      end
    end)

    it("test start with default hash", function()
      add_canary(api1.id, {
        upstream_uri = "/requests/path2",
        percentage = nil,
        steps = 3,
        start = ngx.time() + 2,
        duration = 6
      })
      local ids = generate_consumers(admin_client, {0,1,2}, 3)
      local count = {}
      ngx.sleep(2.5)
      for n = 1, 3 do
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.com",
              ["apikey"] = apikey
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
        end
        assert.are.equal(n, count["/requests/path2"])
        assert.are.equal(3 - n, count["/requests"] or  0)
        count = {}
        ngx.sleep(2)
      end

      -- now all request should route to new target
      for _, apikey in pairs(ids) do
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary1.com",
            ["apikey"] = apikey
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_equal("/requests/path2", json.vars.request_uri)
      end
    end)

    it("test start with default hash and upstream_host", function()
      local server1 = http_server(10, 9, 20002)
      add_canary(api1.id, {
        upstream_host = "127.0.0.1:20002",
        percentage = nil,
        steps = 3,
        start = ngx.time() + 2,
        duration = 6
      })
      local ids = generate_consumers(admin_client, {0,1,2}, 3)
      local count = {}
      ngx.sleep(2.5)
      for n = 1, 3 do
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.com",
              ["apikey"] = apikey
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
        end
        assert.are.equal(n, count["/requests/path2"])
        assert.are.equal(3 - n, count["/requests"] or  0)
        count = {}
        ngx.sleep(2)
      end

      -- now all request should route to new target
      for _, apikey in pairs(ids) do
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary1.com",
            ["apikey"] = apikey
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_equal("/requests/path2", json.vars.request_uri)
      end
      local _, success = server1:join()
      assert.is_equal(9, success)
    end)

    it("test start with hash as `ip`", function()
      add_canary(api1.id, {
        upstream_uri = "/requests/path2",
        percentage = nil,
        steps = 3,
        start = ngx.time() + 2,
        duration = 6,
        hash = "ip",
      })
      local ids = generate_consumers(admin_client, {0,1,2}, 3)
      local count = {}
      ngx.sleep(2.5)
      for n = 1, 3 do
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.com",
              ["apikey"] = apikey
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1

        end
        -- we have 4 consumers, but they should, based on ip, be all in the same target
        if count["/requests/path2"] then
          assert.are.equal(3, count["/requests/path2"])
          assert.is_nil(count["/requests"])
        else
          assert.are.equal(3, count["/requests"])
          assert.is_nil(count["/requests/path2"])
        end
        count = {}
        ngx.sleep(2)
      end

      -- now all request should route to new target
      for _, apikey in pairs(ids) do
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary1.com",
            ["apikey"] = apikey
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_equal("/requests/path2", json.vars.request_uri)
      end
    end)
  end)
end)
