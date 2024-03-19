local helpers           = require "spec.helpers"
local cjson             = require "cjson"
local redis_helper      = require "spec.helpers.redis_helper"


local REDIS_HOST        = helpers.redis_host
local REDIS_PORT        = helpers.redis_port
local REDIS_SSL_PORT    = helpers.redis_ssl_port
local REDIS_SSL_SNI     = helpers.redis_ssl_sni
local REDIS_PASSWORD    = ""
local REDIS_DATABASE    = 1
local UPSTREAM_HOST     = "localhost"
local UPSTREAM_PORT     = helpers.get_available_port()
local UPSTREAM_URL      = string.format("http://%s:%d/always_200", UPSTREAM_HOST, UPSTREAM_PORT)

local fmt               = string.format
local proxy_client      = helpers.proxy_client
local table_insert      = table.insert
local tonumber          = tonumber

local ngx_sleep         = ngx.sleep
local ngx_now           = ngx.now


-- This performs the test up to two times (and no more than two).
-- We are **not** retrying to "give it another shot" in case of a flaky test.
-- The reason why we allow for a single retry in this test suite is because
-- tests are dependent on the value of the current minute. If the minute
-- flips during the test (i.e. going from 03:43:59 to 03:44:00), the result
-- will fail. Since each test takes less than a minute to run, running it
-- a second time right after that failure ensures that another flip will
-- not occur. If the second execution failed as well, this means that there
-- was an actual problem detected by the test.
local function retry(fn)
  if not pcall(fn) then
    ngx_sleep(61 - (ngx_now() % 60))  -- Wait for minute to expire
    fn()
  end
end


local function GET(url, opt)
  local client = proxy_client()
  local res, err  = client:get(url, opt)
  if not res then
    client:close()
    return nil, err
  end

  assert(res:read_body())

  client:close()

  return res
end


local function client_requests(n, proxy_fn)
  local ret = {
    minute_limit     = {},
    minute_remaining = {},

    hour_limit       = {},
    hour_remaining   = {},

    limit            = {},
    remaining        = {},

    status           = {},
    reset            = {},
  }

  for _ = 1, n do
    local res = assert(proxy_fn())

    table_insert(ret.reset, tonumber(res.headers["RateLimit-Reset"]))

    table_insert(ret.status, res.status)

    table_insert(ret.minute_limit, tonumber(res.headers["X-RateLimit-Limit-Minute"]))
    table_insert(ret.minute_remaining, tonumber(res.headers["X-RateLimit-Remaining-Minute"]))

    table_insert(ret.hour_limit, tonumber(res.headers["X-RateLimit-Limit-Hour"]))
    table_insert(ret.hour_remaining, tonumber(res.headers["X-RateLimit-Remaining-Hour"]))

    table_insert(ret.limit, tonumber(res.headers["RateLimit-Limit"]))
    table_insert(ret.remaining, tonumber(res.headers["RateLimit-Remaining"]))

    helpers.wait_timer("rate-limiting", true, "any-finish")
  end

  return ret
end


local function validate_headers(headers, check_minute, check_hour)
  if check_minute then
    assert.same({
      6, 6, 6, 6, 6, 6, 6,
    }, headers.minute_limit)

    assert.same({
      5, 4, 3, 2, 1, 0, 0,
    }, headers.minute_remaining)
  end

  if check_hour then
    for _, v in ipairs(headers.hour_limit) do
      assert(v > 0)
    end

    for _, v in ipairs(headers.hour_remaining) do
      assert(v >= 0)
    end
  end

  assert.same({
    6, 6, 6, 6, 6, 6, 6,
  }, headers.limit)

  assert.same({
    5, 4, 3, 2, 1, 0, 0,
  }, headers.remaining)

  assert.same({
    200, 200, 200, 200, 200, 200, 429,
  }, headers.status)

  for _, reset in ipairs(headers.reset) do
    if check_hour then
      assert.equal(true, reset <= 3600 and reset >= 0)

    elseif check_minute then
      assert.equal(true, reset <= 60 and reset >= 0)

    else
      error("check_hour or check_minute must be true")
    end

  end
end


local function setup_service(admin_client, url)
  local service = assert(admin_client:send({
      method = "POST",
      path = "/services",
      body = {
        url = url,
      },
      headers = {
        ["Content-Type"] = "application/json",
      },
    }))

  return cjson.decode(assert.res_status(201, service))
end

local function setup_route(admin_client, service, paths, protocol)
  protocol = protocol or "http"
  local route = assert(admin_client:send({
      method = "POST",
      path = "/routes",
      body = {
        protocols = { protocol },
        service = { id = service.id, },
        paths = paths,
      },
      headers = {
        ["Content-Type"] = "application/json",
      },
    }))

  return cjson.decode(assert.res_status(201, route))
end

local function setup_rl_plugin(admin_client, conf, service, consumer)
  local plugin

  if service then
    plugin = assert(admin_client:send({
      method = "POST",
      path = "/plugins",
      body = {
        name = "rate-limiting",
        service = { id = service.id, },
        config = conf,
      },
      headers = {
        ["Content-Type"] = "application/json",
      },
    }))

  elseif consumer then
    plugin = assert(admin_client:send({
      method = "POST",
      path = "/plugins",
      body = {
        name = "rate-limiting",
        consumer = { id = consumer.id, },
        config = conf,
      },
      headers = {
        ["Content-Type"] = "application/json",
      },
    }))

  else
    plugin = assert(admin_client:send({
      method = "POST",
      path = "/plugins",
      body = {
        name = "rate-limiting",
        config = conf,
      },
      headers = {
        ["Content-Type"] = "application/json",
      },
    }))
  end

  return cjson.decode(assert.res_status(201, plugin))
end

local function setup_key_auth_plugin(admin_client, conf, service)
  local plugin

  if service then
    plugin = assert(admin_client:send({
      method = "POST",
      path = "/plugins",
      body = {
        name = "key-auth",
        service = { id = service.id, },
        config = conf,
      },
      headers = {
        ["Content-Type"] = "application/json",
      },
    }))

  else
    plugin = assert(admin_client:send({
      method = "POST",
      path = "/plugins",
      body = {
        name = "key-auth",
        config = conf,
      },
      headers = {
        ["Content-Type"] = "application/json",
      },
    }))
  end

  return cjson.decode(assert.res_status(201, plugin))
end

local function setup_consumer(admin_client, username)
  local consumer = assert(admin_client:send({
    method = "POST",
    path = "/consumers",
    body = {
      username = username,
    },
    headers = {
      ["Content-Type"] = "application/json",
    },
  }))

  return cjson.decode(assert.res_status(201, consumer))
end

local function setup_credential(admin_client, consumer, key)
  local credential = assert(admin_client:send({
    method = "POST",
    path = "/consumers/" .. consumer.id .. "/key-auth",
    body = {
      key = key,
    },
    headers = {
      ["Content-Type"] = "application/json",
    },
  }))

  return cjson.decode(assert.res_status(201, credential))
end


local function delete_service(admin_client, service)
  local res = assert(admin_client:send({
    method = "DELETE",
    path = "/services/" .. service.id,
  }))

  assert.res_status(204, res)
end

local function delete_route(admin_client, route)
  local res = assert(admin_client:send({
    method = "DELETE",
    path = "/routes/" .. route.id,
  }))

  assert.res_status(204, res)
end

local function delete_plugin(admin_client, plugin)
  local res = assert(admin_client:send({
    method = "DELETE",
    path = "/plugins/" .. plugin.id,
  }))

  assert.res_status(204, res)
end

local function delete_consumer(admin_client, consumer)
  local res = assert(admin_client:send({
    method = "DELETE",
    path = "/consumers/" .. consumer.id,
  }))

  assert.res_status(204, res)
end

local function delete_credential(admin_client, credential)
  local res = assert(admin_client:send({
    method = "DELETE",
    path = "/consumers/" .. credential.consumer.id .. "/key-auth/" .. credential.id,
  }))

  assert.res_status(204, res)
end


local limit_by_confs = {
  "ip",
  "consumer",
  "credential",
  "service",
  "header",
  "path",
}


local ssl_confs = {
  no_ssl = {
    redis_port = REDIS_PORT,
  },
  ssl_verify = {
    redis_ssl = true,
    redis_ssl_verify = true,
    redis_server_name = REDIS_SSL_SNI,
    redis_port = REDIS_SSL_PORT,
  },
  ssl_no_verify = {
    redis_ssl = true,
    redis_ssl_verify = false,
    redis_server_name = "really.really.really.does.not.exist.host.test",
    redis_port = REDIS_SSL_PORT,
  },
}


local desc

for _, strategy in helpers.each_strategy() do
for __, policy in ipairs({ "local", "cluster", "redis" }) do
for ___, limit_by in ipairs(limit_by_confs) do
for ssl_conf_name, ssl_conf in pairs(ssl_confs) do

if ssl_conf_name ~= "no_ssl" and policy ~= "redis" then
  goto continue
end

desc = fmt("Plugin: rate-limiting #db (access) [strategy: %s] [policy: %s] [limit_by: %s] [redis: %s]",
                 strategy, policy, limit_by, ssl_conf_name)

describe(desc, function()
  local db, https_server, admin_client

  lazy_setup(function()
    _, db = helpers.get_db_utils(strategy, nil, { "rate-limiting", "key-auth" })

    if policy == "redis" then
      redis_helper.reset_redis(REDIS_HOST, REDIS_PORT)

    elseif policy == "cluster" then
      db:truncate("ratelimiting_metrics")
    end

    https_server = helpers.https_server.new(UPSTREAM_PORT)
    https_server:start()

    helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled,rate-limiting,key-auth",
      trusted_ips = "0.0.0.0/0,::/0",
      lua_ssl_trusted_certificate = "spec/fixtures/redis/ca.crt",
    })
  end)


  lazy_teardown(function()
    assert(https_server, "unexpected error")
    https_server:shutdown()
    assert(helpers.stop_kong(), "failed to stop Kong")
  end)

  before_each(function ()
    admin_client = helpers.admin_client()

    if strategy == "cluster" then
      db:truncate("ratelimiting_metrics")
    end

    if policy == "redis" then
      redis_helper.reset_redis(REDIS_HOST, REDIS_PORT)
    end
  end)

  after_each(function()
    admin_client:close()
  end)

  it(fmt("blocks if exceeding limit (single %s)", limit_by), function()
    local test_path = "/test"
    local test_header = "test-header"
    local test_key_name = "test-key"
    local test_credential = "test_credential"

    local service = setup_service(admin_client, UPSTREAM_URL)
    local route = setup_route(admin_client, service, { test_path })
    local rl_plugin = setup_rl_plugin(admin_client, {
      minute              = 6,
      policy              = policy,
      limit_by            = limit_by,
      path                = test_path,                  -- only for limit_by = "path"
      header_name         = test_header,                -- only for limit_by = "header"
      redis = {
        host          = REDIS_HOST,
        port          = ssl_conf.redis_port,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = ssl_conf.redis_ssl,
        ssl_verify    = ssl_conf.redis_ssl_verify,
        server_name   = ssl_conf.redis_server_name,
      }
    }, service)

    local auth_plugin
    local consumer
    local credential

    if limit_by == "consumer" or limit_by == "credential" then
      auth_plugin = setup_key_auth_plugin(admin_client, {
        key_names = { test_key_name },
      }, service)
      consumer = setup_consumer(admin_client, "Bob")
      credential = setup_credential(admin_client, consumer, test_credential)
    end

    finally(function()
      if limit_by == "consumer" or limit_by == "credential" then
        delete_credential(admin_client, credential)
        delete_consumer(admin_client, consumer)
        delete_plugin(admin_client, auth_plugin)
      end

      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route)
      delete_service(admin_client, service)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    local function proxy_fn()
      if limit_by == "ip" or
         limit_by == "path" or
         limit_by == "service" then
        return GET(test_path)
      end

      if limit_by == "header" then
        return GET(test_path, { [test_header] = "test" })
      end

      if limit_by == "consumer" or limit_by == "credential" then
        return GET(test_path, { headers = { [test_key_name] = test_credential }})
      end

      error("unexpected limit_by: " .. limit_by)
    end

    retry(function ()
      validate_headers(client_requests(7, proxy_fn), true)
    end)
  end)

if limit_by == "ip" then
  it("blocks if exceeding limit (multiple ip)", function()
    local test_path = "/test"

    local service = setup_service(admin_client, UPSTREAM_URL)
    local route = setup_route(admin_client, service, { test_path })
    local rl_plugin = setup_rl_plugin(admin_client, {
      minute              = 6,
      policy              = policy,
      limit_by            = "ip",
      redis = {
        host          = REDIS_HOST,
        port          = ssl_conf.redis_port,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = ssl_conf.redis_ssl,
        ssl_verify    = ssl_conf.redis_ssl_verify,
        server_name   = ssl_conf.redis_server_name,
      }
    }, service)

    finally(function()
      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route)
      delete_service(admin_client, service)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    retry(function ()
      for _, ip in ipairs({ "127.0.0.1", "127.0.0.2" }) do
        validate_headers(client_requests(7, function ()
          return GET(test_path, { headers = { ["X-Real-IP"] = ip }})
        end), true)
      end     -- for _, ip in ipairs({ "127.0.0.1", "127.0.0.2" }) do
    end)      -- retry(function ()
  end)        -- it("blocks if exceeding limit (multiple ip)", function()

  it("blocks if exceeding limit #grpc (single ip)", function()
    local test_path = "/hello.HelloService/"

    local service = setup_service(admin_client, helpers.grpcbin_url)
    local route = setup_route(admin_client, service, { test_path }, "grpc")
    local rl_plugin = setup_rl_plugin(admin_client, {
      minute              = 6,
      policy              = policy,
      limit_by            = "ip",
      redis = {
        host          = REDIS_HOST,
        port          = ssl_conf.redis_port,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = ssl_conf.redis_ssl,
        ssl_verify    = ssl_conf.redis_ssl_verify,
        server_name   = ssl_conf.redis_server_name,
      }
    }, service)

    finally(function()
      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route)
      delete_service(admin_client, service)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    retry(function ()
      for i = 1, 6 do
        local ok, res = helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {
            ["-v"] = true,
          },
        }

        assert.is_true(ok, res)

        assert.matches("x%-ratelimit%-limit%-minute: 6", res)
        assert.matches("x%-ratelimit%-remaining%-minute: " .. (6 - i), res)
        assert.matches("ratelimit%-limit: 6", res)
        assert.matches("ratelimit%-remaining: " .. (6 - i), res)

        local reset = tonumber(string.match(res, "ratelimit%-reset: (%d+)"))
        assert.equal(true, reset <= 60 and reset >= 0)

        -- wait for zero-delay timer
        helpers.wait_timer("rate-limiting", true, "any-finish")
      end

      -- Additional request, while limit is 6/minute
      local ok, res = helpers.proxy_client_grpc(){
        service = "hello.HelloService.SayHello",
        opts = {
          ["-v"] = true,
        },
      }
      assert.falsy(ok)
      assert.matches("Code: ResourceExhausted", res)

      assert.matches("ratelimit%-limit: 6", res)
      assert.matches("ratelimit%-remaining: 0", res)

      local retry = tonumber(string.match(res, "retry%-after: (%d+)"))
      assert.equal(true, retry <= 60 and retry > 0)

      local reset = tonumber(string.match(res, "ratelimit%-reset: (%d+)"))
      assert.equal(true, reset <= 60 and reset > 0)
    end)
  end)

  it("hide_client_headers (single ip)", function ()
    local test_path = "/test"

    local service = setup_service(admin_client, UPSTREAM_URL)
    local route = setup_route(admin_client, service, { test_path })
    local rl_plugin = setup_rl_plugin(admin_client, {
      minute              = 6,
      policy              = policy,
      limit_by            = "ip",
      hide_client_headers = true,
      redis = {
        host          = REDIS_HOST,
        port          = ssl_conf.redis_port,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = ssl_conf.redis_ssl,
        ssl_verify    = ssl_conf.redis_ssl_verify,
        server_name   = ssl_conf.redis_server_name,
      }
    }, service)

    finally(function()
      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route)
      delete_service(admin_client, service)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    local res = assert(GET(test_path))

    assert.is_nil(res.headers["X-Ratelimit-Limit-Minute"])
    assert.is_nil(res.headers["X-Ratelimit-Remaining-Minute"])
    assert.is_nil(res.headers["Ratelimit-Limit"])
    assert.is_nil(res.headers["Ratelimit-Remaining"])
    assert.is_nil(res.headers["Ratelimit-Reset"])
    assert.is_nil(res.headers["Retry-After"])
  end)

  it("handles multiple limits (single ip)", function()
    local test_path = "/test"
    local test_header = "test-header"

    local service = setup_service(admin_client, UPSTREAM_URL)
    local route = setup_route(admin_client, service, { test_path })
    local rl_plugin = setup_rl_plugin(admin_client, {
      minute              = 6,
      hour                = 99999,
      policy              = policy,
      limit_by            = limit_by,
      path                = test_path,
      header_name         = test_header,
      redis = {
        host          = REDIS_HOST,
        port          = ssl_conf.redis_port,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = ssl_conf.redis_ssl,
        ssl_verify    = ssl_conf.redis_ssl_verify,
        server_name   = ssl_conf.redis_server_name,
      }
    }, service)

    finally(function()
      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route)
      delete_service(admin_client, service)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    local function proxy_fn()
      return GET(test_path)
    end

    retry(function ()
      validate_headers(client_requests(7, proxy_fn), true, true)
    end)

  end)

  it("expire counter", function()
    local test_path = "/test"

    local service = setup_service(admin_client, UPSTREAM_URL)
    local route = setup_route(admin_client, service, { test_path })
    local rl_plugin = setup_rl_plugin(admin_client, {
      second              = 1,
      policy              = policy,
      limit_by            = "ip",
      redis = {
        host          = REDIS_HOST,
        port          = ssl_conf.redis_port,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = ssl_conf.redis_ssl,
        ssl_verify    = ssl_conf.redis_ssl_verify,
        server_name   = ssl_conf.redis_server_name,
      }
    }, service)

    finally(function()
      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route)
      delete_service(admin_client, service)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    assert
      .with_timeout(15)
      .with_max_tries(10)
      .with_step(0.5) -- the windows is 1 second, we wait 0.5 seconds between each retry,
                      -- that can avoid some unlucky case (we are at the end of the window)
      .ignore_exceptions(false)
      .eventually(function()
        local res1 = GET(test_path, { headers = { ["X-Real-IP"] = "127.0.0.3" }})
        assert.res_status(200, res1)
        assert.are.same(1, tonumber(res1.headers["RateLimit-Limit"]))
        assert.are.same(0, tonumber(res1.headers["RateLimit-Remaining"]))
        assert.is_true(tonumber(res1.headers["ratelimit-reset"]) >= 0)
        assert.are.same(1, tonumber(res1.headers["X-RateLimit-Limit-Second"]))
        assert.are.same(0, tonumber(res1.headers["X-RateLimit-Remaining-Second"]))

        local res2 = GET(test_path, { headers = { ["X-Real-IP"] = "127.0.0.3" }})
        local body2 = assert.res_status(429, res2)
        local json2 = cjson.decode(body2)
        assert.not_nil(json2.message)
        assert.matches("API rate limit exceeded", json2.message)

        ngx_sleep(1)
        local res3 = GET(test_path, { headers = { ["X-Real-IP"] = "127.0.0.3" }})
        assert.res_status(200, res3)
      end)
      .has_no_error("counter should have been cleared after current window")
  end)

  it("blocks with a custom error code and message", function()
    local test_path = "/test"

    local service = setup_service(admin_client, UPSTREAM_URL)
    local route = setup_route(admin_client, service, { test_path })
    local rl_plugin = setup_rl_plugin(admin_client, {
      minute              = 1,
      policy              = policy,
      limit_by            = limit_by,
      path                = test_path,
      redis = {
        host          = REDIS_HOST,
        port          = ssl_conf.redis_port,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = ssl_conf.redis_ssl,
        ssl_verify    = ssl_conf.redis_ssl_verify,
        server_name   = ssl_conf.redis_server_name,
      },
      error_code          = 404,
      error_message       = "Fake Not Found",
    }, service)

    finally(function()
      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route)
      delete_service(admin_client, service)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    local res = GET(test_path)
    assert.res_status(200, res)

    helpers.wait_timer("rate-limiting", true, "any-finish")

    res = GET(test_path)
    local json = cjson.decode(assert.res_status(404, res))
    assert.matches("Fake Not Found", json.message)

  end)      -- it("blocks with a custom error code and message", function()
end         -- if limit_by == "ip" then

if limit_by == "service" then
  it("blocks if exceeding limit (multiple service)", function ()
    local test_path_1, test_path_2 = "/1-test", "/2-test"

    local service_1, service_2 = setup_service(admin_client, UPSTREAM_URL),
                                 setup_service(admin_client, UPSTREAM_URL)
    local route_1, route_2 = setup_route(admin_client, service_1, { test_path_1 }),
                             setup_route(admin_client, service_2, { test_path_2 })
    local rl_plugin = setup_rl_plugin(admin_client, {
      minute              = 6,
      policy              = policy,
      limit_by            = "service",
      redis = {
        host          = REDIS_HOST,
        port          = ssl_conf.redis_port,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = ssl_conf.redis_ssl,
        ssl_verify    = ssl_conf.redis_ssl_verify,
        server_name   = ssl_conf.redis_server_name,
      }
    })

    finally(function()
      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route_1)
      delete_route(admin_client, route_2)
      delete_service(admin_client, service_1)
      delete_service(admin_client, service_2)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    retry(function ()
      for _, path in ipairs({ test_path_1, test_path_2 }) do
        validate_headers(client_requests(7, function()
          return GET(path)
        end), true)
      end     -- for _, path in ipairs({ test_path_1, test_path_2 }) do
    end)      -- retry(function ()
  end)        -- it(fmt("blocks if exceeding limit (multiple %s)", limit_by), function ()
end           -- if limit_by == "service" then

if limit_by == "path" then
  it("blocks if exceeding limit (multiple path)", function()
    local test_path_1, test_path_2 = "/1-test", "/2-test"

    local service = setup_service(admin_client, UPSTREAM_URL)
    local route_1, route_2 = setup_route(admin_client, service, { test_path_1 }),
                             setup_route(admin_client, service, { test_path_2 })
    local rl_plugin = setup_rl_plugin(admin_client, {
      minute              = 6,
      policy              = policy,
      limit_by            = "path",
      path                = test_path_1,
      redis = {
        host          = REDIS_HOST,
        port          = ssl_conf.redis_port,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = ssl_conf.redis_ssl,
        ssl_verify    = ssl_conf.redis_ssl_verify,
        server_name   = ssl_conf.redis_server_name,
      }
    }, service)

    finally(function()
      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route_1)
      delete_route(admin_client, route_2)
      delete_service(admin_client, service)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    retry(function ()
      for _, path in ipairs({ test_path_1, test_path_2 }) do
        validate_headers(client_requests(7, function()
          return GET(path)
        end), true)
      end     -- for _, path in ipairs({ test_path_1, test_path_2 }) do
    end)      -- retry(function ()

  end)        -- it("blocks if exceeding limit (multiple path)", function()
end           -- if limit_by == "path" then

if limit_by == "header" then
  it("blocks if exceeding limit (multiple header)", function()
    local test_path = "/test"
    local test_header_1, test_header_2 = "test-header-1", "test-header-2"

    local service = setup_service(admin_client, UPSTREAM_URL)
    local route = setup_route(admin_client, service, { test_path })
    local rl_plugin = setup_rl_plugin(admin_client, {
      minute              = 6,
      policy              = policy,
      limit_by            = "header",
      header_name         = test_header_1,
      redis = {
        host          = REDIS_HOST,
        port          = ssl_conf.redis_port,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = ssl_conf.redis_ssl,
        ssl_verify    = ssl_conf.redis_ssl_verify,
        server_name   = ssl_conf.redis_server_name,
      }
    }, service)

    finally(function()
      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route)
      delete_service(admin_client, service)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    retry(function ()
      for _, header_name in ipairs({ test_header_1, test_header_2 }) do
        validate_headers(client_requests(7, function()
          return GET(test_path, { headers = { [header_name] = "test" }})
        end), true)
      end     -- for _, header_name in ipairs({ test_header_1, test_header_2 }) do
    end)      -- retry(function ()

  end)        -- it("blocks if exceeding limit (multiple header)", function()
end           -- if limit_by == "header" then

if limit_by == "consumer" or limit_by == "credential" then
  it(fmt("blocks if exceeding limit (multiple %s)", limit_by), function()
    local test_path = "/test"
    local test_key_name = "test-key"
    local test_credential_1, test_credential_2 = "test_credential_1", "test_credential_2"

    local service = setup_service(admin_client, UPSTREAM_URL)
    local route = setup_route(admin_client, service, { test_path })
    local rl_plugin = setup_rl_plugin(admin_client, {
      minute              = 6,
      policy              = policy,
      limit_by            = limit_by,
      redis = {
        host          = REDIS_HOST,
        port          = ssl_conf.redis_port,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = ssl_conf.redis_ssl,
        ssl_verify    = ssl_conf.redis_ssl_verify,
        server_name   = ssl_conf.redis_server_name,
      }
    }, service)
    local auth_plugin = setup_key_auth_plugin(admin_client, {
      key_names = { test_key_name },
    }, service)
    local consumer_1, consumer_2 = setup_consumer(admin_client, "Bob"), setup_consumer(admin_client, "Alice")
    local credential_1, credential_2 = setup_credential(admin_client, consumer_1, test_credential_1),
                                       setup_credential(admin_client, consumer_2, test_credential_2)

    finally(function()
      delete_credential(admin_client, credential_1)
      delete_credential(admin_client, credential_2)
      delete_consumer(admin_client, consumer_1)
      delete_consumer(admin_client, consumer_2)
      delete_plugin(admin_client, auth_plugin)
      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route)
      delete_service(admin_client, service)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    retry(function()
      for _, credential in ipairs({ test_credential_1, test_credential_2 }) do
        validate_headers(client_requests(7, function()
          return GET(test_path, { headers = { [test_key_name] = credential }})
        end), true)
      end     -- for _, credential in ipairs({ test_credential_1, test_credential_2 }) do
    end)      -- retry(function()

  end)        -- it(fmt("blocks if exceeding limit (multiple %s)", limit_by), function()
end           -- if limit_by == "consumer" and limit_by == "credential" then

end)

::continue::

end     -- for ssl_conf_name, ssl_conf in pairs(ssl_confs) do
end     -- for ___, limit_by in ipairs(limit_by_confs) do

desc = fmt("Plugin: rate-limiting fault tolerancy #db (access) [strategy: %s] [policy: %s]",
                 strategy, policy)

describe(desc, function ()
  local db, https_server, admin_client
  local test_path = "/test"
  local service

  local function start_kong()
    return helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled,rate-limiting,key-auth",
      trusted_ips = "0.0.0.0/0,::/0",
      lua_ssl_trusted_certificate = "spec/fixtures/redis/ca.crt",
    })
  end

  local stop_kong = helpers.stop_kong

  lazy_setup(function()
    https_server = helpers.https_server.new(UPSTREAM_PORT)
    https_server:start()
  end)


  lazy_teardown(function()
    assert(https_server, "unexpected error")
    https_server:shutdown()
    local _
    _, db = helpers.get_db_utils(strategy, nil, { "rate-limiting", "key-auth" })
    db:reset()
  end)

  before_each(function ()
    local _
    _, db = helpers.get_db_utils(strategy, nil, { "rate-limiting", "key-auth" })
    db:reset()
    _, db = helpers.get_db_utils(strategy, nil, { "rate-limiting", "key-auth" })

    if policy == "redis" then
      redis_helper.reset_redis(REDIS_HOST, REDIS_PORT)

    elseif policy == "cluster" then
      db:truncate("ratelimiting_metrics")
    end

    assert(start_kong())

    admin_client = helpers.admin_client()

    service = setup_service(admin_client, UPSTREAM_URL)
    setup_route(admin_client, service, { test_path })

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })
  end)

  after_each(function()
    admin_client:close()
    assert(stop_kong())
  end)


if policy == "cluster" then
  it("does not work if an error occurs", function ()
    setup_rl_plugin(admin_client, {
      minute              = 6,
      limit_by            = "ip",
      policy              = policy,
      fault_tolerant      = false,
    }, service)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    retry(function()
      local ret = client_requests(2, function()
        return GET(test_path)
      end)

      assert.same({6, 6}, ret.minute_limit)
      assert.same({5, 4}, ret.minute_remaining)
      assert.same({6, 6}, ret.limit)
      assert.same({5, 4}, ret.remaining)

      for _, reset in ipairs(ret.reset) do
        assert.equal(true, reset <= 60 and reset >= 0)
      end
    end)

    assert(db.connector:query("DROP TABLE ratelimiting_metrics"))

    local res = assert(GET(test_path))
    local body = assert.res_status(500, res)
    local json = cjson.decode(body)
    assert.not_nil(json)
    assert.matches("An unexpected error occurred", json.message)

    assert.falsy(res.headers["X-Ratelimit-Limit-Minute"])
    assert.falsy(res.headers["X-Ratelimit-Remaining-Minute"])
    assert.falsy(res.headers["Ratelimit-Limit"])
    assert.falsy(res.headers["Ratelimit-Remaining"])
    assert.falsy(res.headers["Ratelimit-Reset"])
  end)

  it("keeps working if an error occurs", function ()
    setup_rl_plugin(admin_client, {
      minute              = 6,
      limit_by            = "ip",
      policy              = policy,
      fault_tolerant      = true,
    }, service)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    retry(function()
      local ret = client_requests(2, function()
        return GET(test_path)
      end)

      assert.same({6, 6}, ret.minute_limit)
      assert.same({5, 4}, ret.minute_remaining)
      assert.same({6, 6}, ret.limit)
      assert.same({5, 4}, ret.remaining)
      assert.same({200, 200}, ret.status)

      for _, reset in ipairs(ret.reset) do
        assert.equal(true, reset <= 60 and reset >= 0)
      end
    end)

    assert(db.connector:query("DROP TABLE ratelimiting_metrics"))

    local res = assert(GET(test_path))
    assert.res_status(200, res)
    assert.falsy(res.headers["X-Ratelimit-Limit-Minute"])
    assert.falsy(res.headers["X-Ratelimit-Remaining-Minute"])
    assert.falsy(res.headers["Ratelimit-Limit"])
    assert.falsy(res.headers["Ratelimit-Remaining"])
    assert.falsy(res.headers["Ratelimit-Reset"])

  end)
end     -- if policy == "cluster" then

if policy == "redis" then
  it("does not work if an error occurs", function ()
    setup_rl_plugin(admin_client, {
      minute              = 6,
      policy              = "redis",
      limit_by            = "ip",
      redis = {
        host          = "127.0.0.1",
        port          = 80,                     -- bad redis port
        ssl           = false,
      },
      fault_tolerant      = false,
    }, service)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    local res = assert(GET(test_path))
    local body = assert.res_status(500, res)
    local json = cjson.decode(body)
    assert.not_nil(json)
    assert.matches("An unexpected error occurred", json.message)

    assert.falsy(res.headers["X-Ratelimit-Limit-Minute"])
    assert.falsy(res.headers["X-Ratelimit-Remaining-Minute"])
    assert.falsy(res.headers["Ratelimit-Limit"])
    assert.falsy(res.headers["Ratelimit-Remaining"])
    assert.falsy(res.headers["Ratelimit-Reset"])
  end)

  it("keeps working if an error occurs", function ()
    setup_rl_plugin(admin_client, {
      minute              = 6,
      policy              = "redis",
      limit_by            = "ip",
      redis = {
        host          = "127.0.0.1",
        port          = 80,                     -- bad redis port
        ssl           = false,
      },
      fault_tolerant      = true,
    }, service)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    local res = assert(GET(test_path))
    assert.res_status(200, res)

    assert.falsy(res.headers["X-Ratelimit-Limit-Minute"])
    assert.falsy(res.headers["X-Ratelimit-Remaining-Minute"])
    assert.falsy(res.headers["Ratelimit-Limit"])
    assert.falsy(res.headers["Ratelimit-Remaining"])
    assert.falsy(res.headers["Ratelimit-Reset"])

  end)
end     -- if policy == "redis" then

end)

if policy == "redis" then

desc = fmt("Plugin: rate-limiting with sync_rate #db (access) [strategy: %s]", strategy)

describe(desc, function ()
  local https_server, admin_client

  lazy_setup(function()
    helpers.get_db_utils(strategy, nil, {
      "rate-limiting",
    })

    https_server = helpers.https_server.new(UPSTREAM_PORT)
    https_server:start()

    assert(helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled,rate-limiting,key-auth",
      trusted_ips = "0.0.0.0/0,::/0",
      lua_ssl_trusted_certificate = "spec/fixtures/redis/ca.crt",
      log_level = "error"
    }))

  end)

  lazy_teardown(function()
    https_server:shutdown()
    assert(helpers.stop_kong())
  end)

  before_each(function()
    redis_helper.reset_redis(REDIS_HOST, REDIS_PORT)
    admin_client = helpers.admin_client()
  end)

  after_each(function()
    admin_client:close()
  end)

  it("blocks if exceeding limit", function ()
    local test_path = "/test"

    local service = setup_service(admin_client, UPSTREAM_URL)
    local route = setup_route(admin_client, service, { test_path })
    local rl_plugin = setup_rl_plugin(admin_client, {
      minute              = 6,
      policy              = "redis",
      limit_by            = "ip",
      redis = {
        host          = REDIS_HOST,
        port          = REDIS_PORT,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = false,
      },
      sync_rate           = 10,
    }, service)
    local red = redis_helper.connect(REDIS_HOST, REDIS_PORT)
    local ok, err = red:select(REDIS_DATABASE)
    if not ok then
      error("failed to change Redis database: " .. err)
    end

    finally(function()
      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route)
      delete_service(admin_client, service)
      red:close()
      local shell = require "resty.shell"
      shell.run("cat servroot/logs/error.log", nil, 0)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
    })

    -- initially, the metrics are not written to the redis
    assert(red:dbsize() == 0, "redis db should be empty, but got " .. red:dbsize())

    retry(function ()
      -- exceed the limit
      for _i = 0, 7 do
        GET(test_path)
      end

      -- exceed the limit locally
      assert.res_status(429, GET(test_path))

      -- wait for the metrics to be written to the redis
      helpers.pwait_until(function()
        GET(test_path)
        assert(red:dbsize() == 1, "redis db should have 1 key, but got " .. red:dbsize())
      end, 15)

      -- wait for the metrics expire
      helpers.pwait_until(function()
        assert.res_status(200, GET(test_path))
      end, 61)

    end)

  end)  -- it("blocks if exceeding limit", function ()

end)

end     -- if policy == "redis" then

end     -- for __, policy in ipairs({ "local", "cluster", "redis" }) do


desc = fmt("Plugin: rate-limiting enable globally #db (access) [strategy: %s]", strategy)

describe(desc, function ()
  local https_server, admin_client

  lazy_setup(function()
    helpers.get_db_utils(strategy, nil, {
      "rate-limiting", "key-auth",
    })

    https_server = helpers.https_server.new(UPSTREAM_PORT)
    https_server:start()

    assert(helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled,rate-limiting,key-auth",
      trusted_ips = "0.0.0.0/0,::/0",
      lua_ssl_trusted_certificate = "spec/fixtures/redis/ca.crt",
    }))

  end)

  lazy_teardown(function()
    https_server:shutdown()
    assert(helpers.stop_kong())
  end)

  before_each(function()
    admin_client = helpers.admin_client()
  end)

  after_each(function()
    admin_client:close()
  end)

  it("global for single consumer", function()
    local test_path_1, test_path_2 = "/1-test", "/2-test"
    local test_key_name = "test-key"
    local test_credential = "test-credential"

    local service_1, service_2 = setup_service(admin_client, UPSTREAM_URL),
                                 setup_service(admin_client, UPSTREAM_URL)
    local route_1, route_2 = setup_route(admin_client, service_1, { test_path_1 }),
                             setup_route(admin_client, service_2, { test_path_2 })
    local consumer = setup_consumer(admin_client, "Bob")
    local key_auth_plugin = setup_key_auth_plugin(admin_client, {
      key_names = { test_key_name },
    })
    local rl_plugin = setup_rl_plugin(admin_client, {
      minute              = 6,
      policy              = "local",
      limit_by            = "credential",
      redis = {
        host          = REDIS_HOST,
        port          = REDIS_PORT,
        password      = REDIS_PASSWORD,
        database      = REDIS_DATABASE,
        ssl           = false,
      }
    })
    local credential = setup_credential(admin_client, consumer, test_credential)

    finally(function()
      delete_credential(admin_client, credential)
      delete_consumer(admin_client, consumer)
      delete_plugin(admin_client, key_auth_plugin)
      delete_plugin(admin_client, rl_plugin)
      delete_route(admin_client, route_1)
      delete_route(admin_client, route_2)
      delete_service(admin_client, service_1)
      delete_service(admin_client, service_2)
    end)

    helpers.wait_for_all_config_update({
      override_global_rate_limiting_plugin = true,
      override_global_key_auth_plugin = true,
    })

    retry(function ()
      validate_headers(client_requests(7, function()
        return GET(test_path_1, {
          headers = {
            [test_key_name] = test_credential,
          }
        })
      end), true)

      local ret = client_requests(7, function()
        return GET(test_path_2, {
          headers = {
            [test_key_name] = test_credential,
          }
        })
      end)

      assert.same({
        6, 6, 6, 6, 6, 6, 6,
      }, ret.minute_limit)

      assert.same({
        0, 0, 0, 0, 0, 0, 0,
      }, ret.minute_remaining)

      assert.same({
        6, 6, 6, 6, 6, 6, 6,
      }, ret.limit)

      assert.same({
        0, 0, 0, 0, 0, 0, 0,
      }, ret.remaining)

      assert.same({
        429, 429, 429, 429, 429, 429, 429,
      }, ret.status)

      for _, reset in ipairs(ret.reset) do
        assert.equal(true, reset <= 60 and reset >= 0)
      end
    end)

  end)
end)

end     -- for _, strategy in helpers.each_strategy() do
