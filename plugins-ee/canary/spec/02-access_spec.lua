-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local bu = require "spec.fixtures.balancer_utils"
local math_fmod = math.fmod
local crc32 = ngx.crc32_short
local uuid = require("kong.tools.utils").uuid

local HEALTHY_UPSTREAM_HOST_1 = "127.0.0.1"
local HEALTHY_UPSTREAM_PORT_1 = 20000

local HEALTHY_UPSTREAM_HOST_2 = "127.0.0.1"
local HEALTHY_UPSTREAM_PORT_2 = 20001

local UNHEALTHY_UPSTREAM_HOST = "127.0.0.1"
local UNHEALTHY_UPSTREAM_PORT = 20002
local UNHEALTHY_UPSTREAM_HOST_PORT = UNHEALTHY_UPSTREAM_HOST .. ":" .. UNHEALTHY_UPSTREAM_PORT


local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local upstream_mock = { http_mock = {
  upstream_20000 = [[
    server {
      listen 20000;

      location /clear {
        default_type text/plain;
        content_by_lua_block {
          _G.__upstream_20000_count = 0
          ngx.say("OK")
        }
      }

      location /count {
        default_type text/plain;
        content_by_lua_block {
          local count = _G.__upstream_20000_count or 0
          ngx.say(tostring(count))
        }
      }

      location / {
        default_type text/plain;
        content_by_lua_block {
          local count = _G.__upstream_20000_count or 0
          _G.__upstream_20000_count = count + 1
          ngx.say("OK")
        }
      }
    }
  ]],

  upstream_20001 = [[
    server {
      listen 20001;

      location /clear {
        default_type text/plain;
        content_by_lua_block {
          _G.__upstream_20002_count = 0
          ngx.say("OK")
        }
      }

      location /count {
        default_type text/plain;
        content_by_lua_block {
          local count = _G.__upstream_20002_count or 0
          ngx.say(tostring(count))
        }
      }

      location / {
        default_type application/json;
        content_by_lua_block {
          local count = _G.__upstream_20002_count or 0
          _G.__upstream_20002_count = count + 1

          local body = {
            vars = {
              request_uri = "/requests/path2"
            }
          }
          ngx.say(require("cjson").encode(body))
        }
      }

    }
  ]],

  upstream_20002 = [[
    server {
        listen 20002;

        location /clear {
          default_type text/plain;
          content_by_lua_block {
            _G.__upstream_20001_count = 0
            ngx.say("OK")
          }
        }

        location /count {
          default_type text/plain;
          content_by_lua_block {
            local count = _G.__upstream_20001_count or 0
            ngx.say(tostring(count))
          }
        }

        location / {
          default_type text/plain;
          content_by_lua_block {
            local count = _G.__upstream_20001_count or 0
            _G.__upstream_20001_count = count + 1
            ngx.status = 500
            ngx.exit(ngx.OK)
          }
        }
    }
  ]],
  },
}


local function reset_upstream()
  local upstreams = {
    { host = HEALTHY_UPSTREAM_HOST_1,               port = HEALTHY_UPSTREAM_PORT_1 },
    { host = UNHEALTHY_UPSTREAM_HOST,     port = UNHEALTHY_UPSTREAM_PORT },
    { host = HEALTHY_UPSTREAM_HOST_2,    port = HEALTHY_UPSTREAM_PORT_2 },
  }

  for _, v in ipairs(upstreams) do
    local client = helpers.http_client(v.host, v.port)
    local res = client:send {
      method = "POST",
      path = "/clear",
    }
    local body = assert.response(res).has.status(200)
    client:close()
    assert.same("OK", body)
  end
end


local function get_mock_upstream_successes(host, port)
  local client = helpers.http_client(host, port)
  local res = client:send {
    method = "GET",
    path = "/count",
  }
  local count = tonumber(assert.response(res).has.status(200))
  client:close()
  return count
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


local function continue_after(time)
  assert.eventually(function()
    ngx.update_time()
    return ngx.now() > time
  end)
  .is_truthy()
end


for _, strategy in strategies() do
  describe("Plugin: canary (access) [#" .. strategy .. "]", function()
    local proxy_client, admin_client
    local route1, route2, route3, route4
    local db_strategy = strategy ~= "off" and strategy or nil

    setup(function()
      local bp = helpers.get_db_utils(db_strategy, nil, {
        "canary"
      })

      route1 = bp.routes:insert({
        hosts = { "canary1.test" },
        preserve_host = false,
      })
      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route1.id },
        config = {},
      }

      route2 = bp.routes:insert({
        hosts = { "canary2.test" },
        preserve_host = false,
      })
      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route2.id },
        config = {},
      }

      route3 = bp.routes:insert({
        hosts = { "canary3.test" },
        preserve_host = true,
      })
      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route3.id },
        config = {},
      }

      route4 = bp.routes:insert({
        hosts = { "canary4.test" },
        preserve_host = true,
      })

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = db_strategy,
        plugins = "canary,key-auth,acl",
      }, nil, nil, upstream_mock))
    end)


    teardown(function()
      helpers.stop_kong(nil, true)
    end)



    local test_plugin_id -- retain id to remove again in after_each, max 1 per test
    -- add a canary plugin to an api, with the given config.
    -- in `after_each` handler it will be auto-removed
    local function add_canary(route_id, config)
      local res = assert(admin_client:send {
        method = "POST",
        path = "/routes/" .. route_id .."/plugins",
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

    local function del_canary()
      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/plugins/" .. test_plugin_id,
      })
      assert.response(res).has.status(204)
      test_plugin_id = nil
    end

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
      reset_upstream()
    end)

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

      if proxy_client then
        proxy_client:close()
      end
      if admin_client then
        admin_client:close()
      end
    end)


    describe("Canary", function()

      it("test percentage 50%", function()
        add_canary(route1.id, {
          upstream_uri = "/requests/path2",
          percentage = 50,
          steps = 4,
        })
        local ids = generate_consumers(admin_client, {0,1,2,3}, 4)
        local count = {}
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
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

      it("test percentage 50% with upstream_host and upstream_port", function()
        add_canary(route1.id, {
          upstream_host = HEALTHY_UPSTREAM_HOST_2,
          upstream_port = HEALTHY_UPSTREAM_PORT_2,
          percentage = 50,
          steps = 4,
        })
        local ids = generate_consumers(admin_client, {0,1,2,3}, 4)
        local count = {}
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
              ["apikey"] = apikey
            }
          })
          os.execute("cp servroot/logs/error.log ./error.log")
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
        end

        assert.is_equal(count["/requests/path2"], count["/requests"])

        assert.is_equal(2, get_mock_upstream_successes(HEALTHY_UPSTREAM_HOST_2, HEALTHY_UPSTREAM_PORT_2))
      end)

      it("test 'none' as hash", function()
        add_canary(route1.id, {
          upstream_uri = "/requests/path2",
          percentage = 50,
          steps = 4,
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
              ["Host"] = "canary1.test",
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
        add_canary(route1.id, {
          upstream_uri = "/requests/path2",
          percentage = 50,
          steps = 4,
          hash = "ip",
        })
        local ids = generate_consumers(admin_client, {0,1,2,3}, 4)
        local count = {}
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
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

      it("test 'header' as hash", function()
        add_canary(route1.id, {
          upstream_uri = "/requests/path2",
          percentage = 50,
          steps = 4,
          hash = "header",
          hash_header = "X-My-Hash",
        })
        local ids = generate_consumers(admin_client, {0,1,2,3}, 4)
        local count = {}
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
              ["apikey"] = apikey,
              ["X-My-Hash"] = "1234"
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
        end
        -- we have 4 consumers, but they should, based on same header value, be all in the same target
        if count["/requests/path2"] then
          assert.are.equal(4, count["/requests/path2"])
          assert.is_nil(count["/requests"])
        else
          assert.are.equal(4, count["/requests"])
          assert.is_nil(count["/requests/path2"])
        end
      end)

      it("test 'allow' consumers", function()
        add_canary(route1.id, {
          upstream_uri = "/requests/path2",
          hash = "allow",
          groups = { "mycanary", "yourcanary" }
        })
        local ids = generate_consumers(admin_client, {1,2,3}, 4)
        local count = {}
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
              ["apikey"] = apikey
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
        end
        -- no consumer is part of the canary groups, so all stay put at `/requests`
        assert.is_nil(count["/requests/path2"])
        assert.are.equal(3, count["/requests"])

        -- add the 3 consumers to groups
        for i, id in pairs(ids) do
          local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/" .. id .."/acls",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              group = ({ "mycanary", "yourcanary", "nocanary"})[i],
            }
          })
          assert.response(res).has.status(201)
        end
        -- now try again
        count = {}
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
              ["apikey"] = apikey
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
        end
        -- two consumer are part of the canary groups, last one is in another group
        assert.are.equal(2, count["/requests/path2"])
        assert.are.equal(1, count["/requests"])
      end)

      it("test 'allow' with no consumer identified", function()
        add_canary(route4.id, {
          upstream_uri = "/requests/path2",
          hash = "allow",
          groups = { "mycanary", "yourcanary" }
        })
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary4.test",
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.are.equal("/requests", json.vars.request_uri)
      end)

      it("test 'deny' consumers", function()
        add_canary(route1.id, {
          upstream_uri = "/requests/path2",
          hash = "deny",
          groups = { "mycanary", "yourcanary" }
        })
        local ids = generate_consumers(admin_client, {1,2,3}, 4)
        local count = {}
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
              ["apikey"] = apikey
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
        end
        -- no consumer is part of the canary groups, so all move over
        assert.are_equal(3, count["/requests/path2"])
        assert.is_nil(count["/requests"])

        -- add the 3 consumers to groups
        for i, id in pairs(ids) do
          local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/" .. id .."/acls",
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = {
              group = ({ "mycanary", "yourcanary", "nocanary"})[i],
            }
          })
          assert.response(res).has.status(201)
        end
        -- now try again
        count = {}
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
              ["apikey"] = apikey
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
        end
        -- two consumer are part of the canary groups, last one is in another group
        assert.are.equal(1, count["/requests/path2"])
        assert.are.equal(2, count["/requests"])
      end)

      it("test 'deny' with no consumer identified", function()
        add_canary(route4.id, {
          upstream_uri = "/requests/path2",
          hash = "deny",
          groups = { "mycanary", "yourcanary" }
        })
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary4.test",
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.are.equal("/requests/path2", json.vars.request_uri)
      end)

      it("test start with default hash", function()
        local ids = generate_consumers(admin_client, {0,1,2}, 3)
        local try = 0
      ::retry::
        assert(try < 10, "exceeds the max number of tries")
        try = try + 1

        if test_plugin_id then
          del_canary()
        end

        local steps = 3
        local duration_per_step = 3
        local duration = steps * duration_per_step
        ngx.update_time()
        local start = ngx.time() + 2
        add_canary(route1.id, {
          upstream_uri = "/requests/path2",
          percentage = nil,
          steps = steps,
          start = start,
          duration = duration,
        })
        -- The expected behavior of this test depends on the server-side time.
        -- We need to make sure all the requests are processed in the same expected step.
        -- So we measure the starting time and end time of the requests.
        -- If they are not processed in the expected time range, we'll retry the test.
        -- But even then we can't guarantee the server-side time and the client-side time
        -- are perfectly synchronized, so it's better to add a margin.
        -- margins:   v     v     v     v
        -- requests:   |...| |...| |...|
        -- steps:     |  1  |  2  |  3  |
        for n = 1, steps do
          local count = {}
          local left_border = start + (n - 1) * duration_per_step + 0.5  -- 0.5s margin
          local right_border = start + n * duration_per_step - 0.5       -- 0.5s margin
          continue_after(left_border)

          local proxy_client = helpers.proxy_client()
          for _, apikey in pairs(ids) do
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/requests",
              headers = {
                ["Host"] = "canary1.test",
                ["apikey"] = apikey
              }
            })
            assert.response(res).has.status(200)
            local json = assert.response(res).has.jsonbody()
            count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
          end
          proxy_client:close()

          -- make sure all the requests are counted in the current step
          ngx.update_time()
          if ngx.now() > right_border then
            goto retry
          end

          assert.are.equal(n, count["/requests/path2"])
          assert.are.equal(3 - n, count["/requests"] or  0)
        end

        continue_after(start + duration + 0.5) -- 0.5s margin

        -- now all request should route to new target
        local proxy_client = helpers.proxy_client()
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
              ["apikey"] = apikey
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          assert.is_equal("/requests/path2", json.vars.request_uri)
        end
        proxy_client:close()
      end)

      it("test start with default hash and upstream_host", function()
        local ids = generate_consumers(admin_client, {0,1,2}, 3)
        local try = 0
      ::retry::
        assert(try < 10, "exceeds the max number of tries")
        try = try + 1

        if test_plugin_id then
          del_canary()
        end

        local steps = 3
        local duration_per_step = 3
        local duration = steps * duration_per_step
        ngx.update_time()
        local start = ngx.time() + 2
        add_canary(route1.id, {
          upstream_host = HEALTHY_UPSTREAM_HOST_2,
          upstream_port = HEALTHY_UPSTREAM_PORT_2,
          percentage = nil,
          steps = steps,
          start = start,
          duration = duration,
        })

        -- The expected behavior of this test depends on the server-side time.
        -- We need to make sure all the requests are processed in the same expected step.
        -- So we measure the starting time and end time of the requests.
        -- If they are not processed in the expected time range, we'll retry the test.
        -- But even then we can't guarantee the server-side time and the client-side time
        -- are perfectly synchronized, so it's better to add a margin.
        -- margins:   v     v     v     v
        -- requests:   |...| |...| |...|
        -- steps:     |  1  |  2  |  3  |
        for n = 1, steps do
          local count = {}
          local left_border = start + (n - 1) * duration_per_step + 0.5  -- 0.5s margin
          local right_border = start + n * duration_per_step - 0.5       -- 0.5s margin
          continue_after(left_border)

          local proxy_client = helpers.proxy_client()
          for _, apikey in pairs(ids) do
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/requests",
              headers = {
                ["Host"] = "canary1.test",
                ["apikey"] = apikey
              }
            })
            assert.response(res).has.status(200)
            local json = assert.response(res).has.jsonbody()
            count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
          end
          proxy_client:close()

          -- make sure all the requests are counted in the current step
          ngx.update_time()
          if ngx.now() > right_border then
            goto retry
          end

          assert.are.equal(n, count["/requests/path2"])
          assert.are.equal(3 - n, count["/requests"] or  0)
        end

        continue_after(start + duration + 0.5) -- 0.5s margin

        -- now all request should route to new target
        local proxy_client = helpers.proxy_client()
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
              ["apikey"] = apikey
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          assert.is_equal("/requests/path2", json.vars.request_uri)
        end
        proxy_client:close()

        assert.is_equal(9, get_mock_upstream_successes(HEALTHY_UPSTREAM_HOST_2, HEALTHY_UPSTREAM_PORT_2))
      end)

      it("test start with hash as `ip`", function()
        local ids = generate_consumers(admin_client, {0,1,2}, 3)
        local try = 0
      ::retry::
        assert(try < 10, "exceeds the max number of tries")
        try = try + 1

        if test_plugin_id then
          del_canary()
        end

        local steps = 3
        local duration_per_step = 3
        local duration = steps * duration_per_step
        ngx.update_time()
        local start = ngx.time() + 2
        add_canary(route1.id, {
          upstream_uri = "/requests/path2",
          percentage = nil,
          steps = steps,
          start = start,
          duration = duration,
          hash = "ip",
        })

        -- The expected behavior of this test depends on the server-side time.
        -- We need to make sure all the requests are processed in the same expected step.
        -- So we measure the starting time and end time of the requests.
        -- If they are not processed in the expected time range, we'll retry the test.
        -- But even then we can't guarantee the server-side time and the client-side time
        -- are perfectly synchronized, so it's better to add a margin.
        -- margins:   v     v     v     v
        -- requests:   |...| |...| |...|
        -- steps:     |  1  |  2  |  3  |
        for n = 1, steps do
          local count = {}
          local left_border = start + (n - 1) * duration_per_step + 0.5  -- 0.5s margin
          local right_border = start + n * duration_per_step - 0.5       -- 0.5s margin
          continue_after(left_border)

          local proxy_client = helpers.proxy_client()
          for _, apikey in pairs(ids) do
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/requests",
              headers = {
                ["Host"] = "canary1.test",
                ["apikey"] = apikey
              }
            })
            assert.response(res).has.status(200)
            local json = assert.response(res).has.jsonbody()
            count[json.vars.request_uri] = (count[json.vars.request_uri] or  0) + 1
          end
          proxy_client:close()

          -- make sure all the requests are counted in the current step
          ngx.update_time()
          if ngx.now() > right_border then
            goto retry
          end

          -- we have 4 consumers, but they should, based on ip, be all in the same target
          if count["/requests/path2"] then
            assert.are.equal(3, count["/requests/path2"])
            assert.is_nil(count["/requests"])
          else
            assert.are.equal(3, count["/requests"])
            assert.is_nil(count["/requests/path2"])
          end
        end

        continue_after(start + duration + 0.5) -- 0.5s margin

        -- now all request should route to new target
        local proxy_client = helpers.proxy_client()
        for _, apikey in pairs(ids) do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
              ["apikey"] = apikey
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          assert.is_equal("/requests/path2", json.vars.request_uri)
        end
        proxy_client:close()
      end)

      it("test 'preserve_host' setting on route", function()
        add_canary(route2.id, {
          upstream_uri = "/requests/path2",
          percentage = 100,  -- move everything to new upstream
          steps = 3,
          hash = "consumer",
        })
        add_canary(route3.id, {
          upstream_uri = "/requests/path2",
          percentage = 100,  -- move everything to new upstream
          steps = 3,
          hash = "consumer",
        })
        local ids = generate_consumers(admin_client, {0,1,2}, 3)
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary2.test",   --> preserve_host == false
            ["apikey"] = ids[1] -- any of the 3 ids will do here
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.are.equal("127.0.0.1", json.vars.host)

        res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary3.test",   --> preserve_host == true
            ["apikey"] = ids[1] -- any of the 3 ids will do here
          }
        })
        assert.response(res).has.status(200)
        json = assert.response(res).has.jsonbody()
        assert.are.equal("canary3.test", json.vars.host)
      end)

      it("test 'canary_by_header_name' is configured and request header value == never", function()
        add_canary(route1.id, {
          upstream_uri = "/requests/path2",
          percentage = 50,
          steps = 4,
          hash = "none",
          canary_by_header_name = "X-Canary-Override",
        })
        -- only use 1 consumer, which should still randomly end up in all targets
        local apikey = generate_consumers(admin_client, {0}, 4)[0]
        local count = {
          ["/requests/path2"] = 0,
          ["/requests"] = 0,
        }
        local timeout = ngx.now() + 30
        while count["/requests"] < 4 do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
              ["apikey"] = apikey,
              ["X-Canary-Override"] = "never",
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = count[json.vars.request_uri] + 1
          assert(ngx.now() < timeout, "timeout")
        end
        assert(count["/requests"] == 4 )
        assert(count["/requests/path2"] == 0 )
      end)

      it("test 'canary_by_header_name' is configured and request header value == always", function()
        add_canary(route1.id, {
          upstream_uri = "/requests/path2",
          percentage = 50,
          steps = 4,
          hash = "none",
          canary_by_header_name = "X-Canary-Override",
        })
        -- only use 1 consumer, which should still randomly end up in all targets
        local apikey = generate_consumers(admin_client, {0}, 4)[0]
        local count = {
          ["/requests/path2"] = 0,
          ["/requests"] = 0,
        }
        local timeout = ngx.now() + 30
        while count["/requests/path2"] < 4 do
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/requests",
            headers = {
              ["Host"] = "canary1.test",
              ["apikey"] = apikey,
              ["X-Canary-Override"] = "always",
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = count[json.vars.request_uri] + 1
          assert(ngx.now() < timeout, "timeout")
        end
        assert(count["/requests"] == 0 )
        assert(count["/requests/path2"] == 4 )
      end)

      it("test 'canary_by_header_name' is configured and header in request is neither 'always' nor 'never'", function()
        add_canary(route1.id, {
          upstream_uri = "/requests/path2",
          percentage = 50,
          steps = 4,
          hash = "none",
          canary_by_header_name = "X-Canary-Override",
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
              ["Host"] = "canary1.test",
              ["apikey"] = apikey,
              ["X-Canary-Override"] = "foo",
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = count[json.vars.request_uri] + 1
          assert(ngx.now() < timeout, "timeout")
        end
      end)

      it("test 'canary_by_header_name' is configured but header is not provided in request", function()
        add_canary(route1.id, {
          upstream_uri = "/requests/path2",
          percentage = 50,
          steps = 4,
          hash = "none",
          canary_by_header_name = "X-Canary-Override",
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
              ["Host"] = "canary1.test",
              ["apikey"] = apikey,
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          count[json.vars.request_uri] = count[json.vars.request_uri] + 1
          assert(ngx.now() < timeout, "timeout")
        end
      end)
    end)
    describe("Canary healthchecks", function()
      local route5, canary_upstream_id
      local res

      setup(function()
        -- reopen clients to avoid closed connections
        if proxy_client then
          proxy_client:close()
        end
        if admin_client then
          admin_client:close()
        end

        proxy_client = helpers.proxy_client()
        admin_client = helpers.admin_client()

        res = assert(admin_client:send {
          method = "POST",
          path = "/services",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            name = "s1",
            url= string.format("http://%s:%d", HEALTHY_UPSTREAM_HOST_1, HEALTHY_UPSTREAM_PORT_1)
          }
        })
        assert.response(res).has.status(201)

        res = assert(admin_client:send {
          method = "POST",
          path = "/services/s1/routes",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            hosts = { "canary5.test" }
          }
        })
        assert.response(res).has.status(201)
        route5 = assert.response(res).has.jsonbody()

        res = assert(admin_client:send {
          method = "POST",
          path = "/upstreams",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            name = "canary",
          }
        })
        assert.response(res).has.status(201)

        res = assert(admin_client:send {
          method = "POST",
          path = "/upstreams/canary/targets",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            target = UNHEALTHY_UPSTREAM_HOST_PORT,
          }
        })
        local body = assert.response(res).has.status(201)
        canary_upstream_id = require("cjson").decode(body).upstream.id
      end)

      it("doesn't fallback if healthchecks aren't enabled #flaky", function()
        add_canary(route5.id, {
          percentage = 100,
          hash = "none",
          upstream_host = "canary",
          -- upstream_port = UNHEALTHY_UPSTREAM_PORT,
          upstream_fallback = true,
        })

        -- healthchecks aren't enabled, so the canary upstream applies
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "canary5.test",
          }
        })

        -- it changes the upstream
        assert.response(res).has.status(500)

        assert.is_equal(1, get_mock_upstream_successes(UNHEALTHY_UPSTREAM_HOST, UNHEALTHY_UPSTREAM_PORT))
      end)
      it("doesn't fallback if upstream is reported healthy #flaky", function()
        add_canary(route5.id, {
          percentage = 100,
          hash = "none",
          upstream_host = "canary",
          -- upstream_port = UNHEALTHY_UPSTREAM_PORT,
          upstream_fallback = true,
        })

        -- enable healthchecks (passive, but it doesn't matter, as all we care
        -- in this test is the health status and we can set it manually)
        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/upstreams/canary",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            healthchecks = {
              passive = {
                unhealthy = {
                  http_failures = 1,
                },
              },
            },
          },
        })
        assert.response(res).has.status(200)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "canary5.test",
          }
        })
        -- it still went to the canary upstream, as there was still no health
        -- status (first request/response going through the passive healthchecker)
        assert.response(res).has.status(500)

        bu.poll_wait_health(canary_upstream_id, UNHEALTHY_UPSTREAM_HOST, UNHEALTHY_UPSTREAM_PORT, "UNHEALTHY")

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "canary5.test",
          }
        })
        -- this is the second request; as the first one resulted in a 500, the
        -- health status was updated and the fallback will take place
        assert.response(res).has.status(200)

        -- if we manually mark it as healthy, the canary will apply and we will
        -- get a 500 from the canary upstream
        local res = assert(admin_client:send {
          method = "PUT",
          path = "/upstreams/canary/targets/" .. UNHEALTHY_UPSTREAM_HOST_PORT .. "/healthy",
        })
        assert.response(res).has.status(204)

        bu.poll_wait_health(canary_upstream_id, UNHEALTHY_UPSTREAM_HOST, UNHEALTHY_UPSTREAM_PORT, "HEALTHY")

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "canary5.test",
          }
        })
        assert.response(res).has.status(500)

        assert.is_equal(2, get_mock_upstream_successes(UNHEALTHY_UPSTREAM_HOST, UNHEALTHY_UPSTREAM_PORT))
      end)
      it("does fallback if upstream isn't healthy #flaky", function()
        add_canary(route5.id, {
          percentage = 100,
          hash = "none",
          upstream_host = "canary",
          -- upstream_port = UNHEALTHY_UPSTREAM_PORT,
          upstream_fallback = true,
        })

        -- mark it as healthy - not strictly needed, but helps keeping the
        -- this test idempotent
        res = assert(admin_client:send {
          method = "PUT",
          path = "/upstreams/canary/targets/" .. UNHEALTHY_UPSTREAM_HOST_PORT .. "/healthy",
        })
        assert.response(res).has.status(204)

        bu.poll_wait_health(canary_upstream_id, UNHEALTHY_UPSTREAM_HOST, UNHEALTHY_UPSTREAM_PORT, "HEALTHY")

        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/upstreams/canary",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            healthchecks = {
              passive = {
                unhealthy = {
                  http_failures = 1,
                },
              },
            },
          },
        })
        assert.response(res).has.status(200)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "canary5.test",
          }
        })

        -- it still went to the canary upstream, as the health status
        -- did not get updated yet
        assert.response(res).has.status(500)

        bu.poll_wait_health(canary_upstream_id, UNHEALTHY_UPSTREAM_HOST, UNHEALTHY_UPSTREAM_PORT, "UNHEALTHY")

        res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "canary5.test",
          }
        })

        -- this is the second request; as the first one resulted in a 500, the
        -- health status was updated and the fallback will take place
        assert.response(res).has.status(200)

        assert.is_equal(1, get_mock_upstream_successes(UNHEALTHY_UPSTREAM_HOST, UNHEALTHY_UPSTREAM_PORT))
      end)
    end)
  end)
end
