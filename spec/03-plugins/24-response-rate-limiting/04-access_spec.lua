local cjson          = require "cjson"
local helpers        = require "spec.helpers"
local redis_helper   = require "spec.helpers.redis_helper"

local REDIS_HOST      = helpers.redis_host
local REDIS_PORT      = helpers.redis_port
local REDIS_SSL_PORT  = helpers.redis_ssl_port
local REDIS_SSL_SNI   = helpers.redis_ssl_sni
local REDIS_PASSWORD  = ""
local REDIS_DATABASE  = 1

local ITERATIONS = 6
local escape_uri = ngx.escape_uri
local encode_args = ngx.encode_args

local fmt = string.format


local proxy_client = helpers.proxy_client


-- wait for server timestamp reaching the ceiling of client timestamp secs
-- e.g. if the client time is 1.531 secs, we want to start the test period
-- at 2.000 of server time, so that we could have as close as 1 sec to 
-- avoid flaky caused by short period(e.g. server start at 1.998 and it soon
-- exceed the time period)
local function wait_server_sync(headers, api_key)
  ngx.update_time()
  local now = ngx.now()
  local secs = math.ceil(now)
  local path = api_key and "/timestamp?apikey="..api_key or "/timestamp"
  helpers.wait_until(function()
    local res = proxy_client():get(path, {
      headers = headers,
    })
    assert(res.status == 200)
    local ts = res.headers["Server-Time"]
    return res.status == 200 and math.floor(tonumber(ts)) == secs
  end, 1, 0.1)
end

-- wait for the remain counter of ratelimintg reaching the expected number.
-- kong server may need some time to sync the remain counter in db/redis, it's
-- better to wait for the definite status then just wait for some time randonly
-- 'path': the url to get remaining counter but not consume the rate 
-- 'expected': the expected number of remaining ratelimit counters
-- 'expected_status': the expected resp status which is 200 by default
local function wait_remaining_sync(path, headers, expected, expected_status, api_key)
  local res
  if api_key then
    path = path .. "?apikey="..api_key
  end
  helpers.wait_until(function()
    res = proxy_client():get(path, {
      headers = headers,
    })
    -- if expected_status is not 200, just check the status, not counter.
    if expected_status and expected_status ~= 200 then
      return res.status == expected_status
    end
    -- check every expected counter specified
    for k, v in pairs(expected) do
      if tonumber(res.headers[k]) ~= v then
        return false
      end
    end
    return res.status == 200
  end, 1)
  return res
end

local redis_confs = {
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


local function test_limit(path, uri_args, host, limit)
  local full_path = path .. "?" .. encode_args(uri_args)
  limit = limit or ITERATIONS
  for i = 1, limit do
    local res = proxy_client():get(full_path, {
      headers = { Host = host:format(i) },
    })
    assert.res_status(200, res)
  end

  -- wait for async timer to increment the limit
  wait_remaining_sync(path, { Host = host:format(1) }, {["x-ratelimit-remaining-video-second"] = 0}, 200, uri_args["apikey"])

  local res = proxy_client():get(full_path, {
    headers = { Host = host:format(1) },
  })
  assert.res_status(429, res)
  assert.equal(limit, tonumber(res.headers["x-ratelimit-limit-video-second"]))
  assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-video-second"]))
end


local function init_db(strategy, policy)
  local bp = helpers.get_db_utils(strategy, {
    "routes",
    "services",
    "plugins",
    "consumers",
    "keyauth_credentials",
  })

  if policy == "redis" then
    redis_helper.reset_redis(REDIS_HOST, REDIS_PORT)
  end

  return bp
end


for _, strategy in helpers.each_strategy() do
  for _, policy in ipairs({"local", "cluster", "redis"}) do

    for redis_conf_name, redis_conf in pairs(redis_confs) do
      if redis_conf_name ~= "no_ssl" and policy ~= "redis" then
        goto continue
      end

      describe(fmt("Plugin: response-ratelimiting (access) with policy: #%s #%s [#%s]", redis_conf_name, policy, strategy), function()

        lazy_setup(function()
          local bp = init_db(strategy, policy)

          local consumer1 = bp.consumers:insert {custom_id = "provider_123"}
          bp.keyauth_credentials:insert {
            key      = "apikey123",
            consumer = { id = consumer1.id },
          }

          local consumer2 = bp.consumers:insert {custom_id = "provider_124"}
          bp.keyauth_credentials:insert {
            key      = "apikey124",
            consumer = { id = consumer2.id },
          }

          local route1 = bp.routes:insert {
            hosts      = { "test1.test" },
            protocols  = { "http", "https" },
          }

          bp.response_ratelimiting_plugins:insert({
            route = { id = route1.id },
            config   = {
              fault_tolerant    = false,
              policy            = policy,
              redis = {
                host        = REDIS_HOST,
                port        = redis_conf.redis_port,
                ssl         = redis_conf.redis_ssl,
                ssl_verify  = redis_conf.redis_ssl_verify,
                server_name = redis_conf.redis_server_name,
                password    = REDIS_PASSWORD,
                database    = REDIS_DATABASE,
              },
              limits            = { video = { second = ITERATIONS } },
            },
          })

          local route2 = bp.routes:insert {
            hosts      = { "test2.test" },
            protocols  = { "http", "https" },
          }

          bp.response_ratelimiting_plugins:insert({
            route = { id = route2.id },
            config   = {
              fault_tolerant    = false,
              policy            = policy,
              redis = {
                host        = REDIS_HOST,
                port        = redis_conf.redis_port,
                ssl         = redis_conf.redis_ssl,
                ssl_verify  = redis_conf.redis_ssl_verify,
                server_name = redis_conf.redis_server_name,
                password    = REDIS_PASSWORD,
                database    = REDIS_DATABASE,
              },
              limits            = { video = { second = ITERATIONS*2, minute = ITERATIONS*4 },
                                    image = { second = ITERATIONS } },
            },
          })

          local route3 = bp.routes:insert {
            hosts      = { "test3.test" },
            protocols  = { "http", "https" },
          }

          bp.plugins:insert {
            name     = "key-auth",
            route = { id = route3.id },
          }

          bp.response_ratelimiting_plugins:insert({
            route = { id = route3.id },
            config   = {
              policy = policy,
              redis = {
                host        = REDIS_HOST,
                port        = REDIS_PORT,
                password    = REDIS_PASSWORD,
                database    = REDIS_DATABASE,
              },
              limits = { video = { second = ITERATIONS - 3 }
            } },
          })

          bp.response_ratelimiting_plugins:insert({
            route = { id = route3.id },
            consumer = { id = consumer1.id },
            config      = {
              fault_tolerant    = false,
              policy            = policy,
              redis = {
                host        = REDIS_HOST,
                port        = redis_conf.redis_port,
                ssl         = redis_conf.redis_ssl,
                ssl_verify  = redis_conf.redis_ssl_verify,
                server_name = redis_conf.redis_server_name,
                password    = REDIS_PASSWORD,
                database    = REDIS_DATABASE,
              },
              limits            = { video = { second = ITERATIONS - 2 } },
            },
          })

          local route4 = bp.routes:insert {
            hosts      = { "test4.test" },
            protocols  = { "http", "https" },
          }

          bp.response_ratelimiting_plugins:insert({
            route = { id = route4.id },
            config   = {
              fault_tolerant    = false,
              policy            = policy,
              redis = {
                host        = REDIS_HOST,
                port        = redis_conf.redis_port,
                ssl         = redis_conf.redis_ssl,
                ssl_verify  = redis_conf.redis_ssl_verify,
                server_name = redis_conf.redis_server_name,
                password    = REDIS_PASSWORD,
                database    = REDIS_DATABASE,
              },
              limits            = {
                video = { second = ITERATIONS * 2 + 2 },
                image = { second = ITERATIONS }
              },
            }
          })

          local route7 = bp.routes:insert {
            hosts      = { "test7.test" },
            protocols  = { "http", "https" },
          }

          bp.response_ratelimiting_plugins:insert({
            route = { id = route7.id },
            config   = {
              fault_tolerant           = false,
              policy                   = policy,
              redis = {
                host        = REDIS_HOST,
                port        = redis_conf.redis_port,
                ssl         = redis_conf.redis_ssl,
                ssl_verify  = redis_conf.redis_ssl_verify,
                server_name = redis_conf.redis_server_name,
                password    = REDIS_PASSWORD,
                database    = REDIS_DATABASE,
              },
              block_on_first_violation = true,
              limits                   = {
                video = {
                  second = ITERATIONS,
                  minute = ITERATIONS * 2,
                },
                image = {
                  second = 4,
                },
              },
            }
          })

          local route8 = bp.routes:insert {
            hosts      = { "test8.test" },
            protocols  = { "http", "https" },
          }

          bp.response_ratelimiting_plugins:insert({
            route = { id = route8.id },
            config   = {
              fault_tolerant    = false,
              policy            = policy,
              redis = {
                host        = REDIS_HOST,
                port        = redis_conf.redis_port,
                ssl         = redis_conf.redis_ssl,
                ssl_verify  = redis_conf.redis_ssl_verify,
                server_name = redis_conf.redis_server_name,
                password    = REDIS_PASSWORD,
                database    = REDIS_DATABASE,
              },
              limits            = { video = { second = ITERATIONS, minute = ITERATIONS*2 },
                                    image = { second = ITERATIONS-1 } },
            }
          })

          local route9 = bp.routes:insert {
            hosts      = { "test9.test" },
            protocols  = { "http", "https" },
          }

          bp.response_ratelimiting_plugins:insert({
            route = { id = route9.id },
            config   = {
              fault_tolerant      = false,
              policy              = policy,
              hide_client_headers = true,
              redis = {
                host        = REDIS_HOST,
                port        = redis_conf.redis_port,
                ssl         = redis_conf.redis_ssl,
                ssl_verify  = redis_conf.redis_ssl_verify,
                server_name = redis_conf.redis_server_name,
                password    = REDIS_PASSWORD,
                database    = REDIS_DATABASE,
              },
              limits              = { video = { second = ITERATIONS } },
            }
          })


          local service10 = bp.services:insert()
          bp.routes:insert {
            hosts = { "test-service1.test" },
            service = service10,
          }
          bp.routes:insert {
            hosts = { "test-service2.test" },
            service = service10,
          }

          bp.response_ratelimiting_plugins:insert({
            service = { id = service10.id },
            config = {
              fault_tolerant    = false,
              policy            = policy,
              redis = {
                host        = REDIS_HOST,
                port        = redis_conf.redis_port,
                ssl         = redis_conf.redis_ssl,
                ssl_verify  = redis_conf.redis_ssl_verify,
                server_name = redis_conf.redis_server_name,
                password    = REDIS_PASSWORD,
                database    = REDIS_DATABASE,
              },
              limits            = { video = { second = ITERATIONS } },
            }
          })

          local grpc_service = assert(bp.services:insert {
            name = "grpc",
            url = helpers.grpcbin_url,
          })

          assert(bp.routes:insert {
            protocols = { "grpc" },
            paths = { "/hello.HelloService/" },
            service = grpc_service,
          })

          bp.response_ratelimiting_plugins:insert({
            service = { id = grpc_service.id },
            config = {
              fault_tolerant    = false,
              policy            = policy,
              redis = {
                host        = REDIS_HOST,
                port        = redis_conf.redis_port,
                ssl         = redis_conf.redis_ssl,
                ssl_verify  = redis_conf.redis_ssl_verify,
                server_name = redis_conf.redis_server_name,
                password    = REDIS_PASSWORD,
                database    = REDIS_DATABASE,
              },
              limits            = { video = { second = ITERATIONS } },
            }
          })

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            lua_ssl_trusted_certificate = "spec/fixtures/redis/ca.crt",
          }))
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        describe("Without authentication (IP address)", function()

          it("returns remaining counter", function()
            local host = "test1.test"
            wait_server_sync( { Host = host })

            local n = math.floor(ITERATIONS / 2)
            for _ = 1, n do
              local res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=1"), {
                headers = { Host = host },
              })
              assert.res_status(200, res)
            end

            wait_remaining_sync("/response-headers", { Host = "test1.test" }, {["x-ratelimit-remaining-video-second"] = ITERATIONS - n})

            local res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=1"), {
              headers = { Host = host },
            })
            assert.res_status(200, res)
            assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-video-second"]))
            assert.equal(ITERATIONS - n - 1, tonumber(res.headers["x-ratelimit-remaining-video-second"]))
          end)

          it("returns remaining counter #grpc", function()
            wait_server_sync({ Host = "test1.test" })

            local ok, res = helpers.proxy_client_grpc(){
              service = "hello.HelloService.SayHello",
              opts = {
                ["-v"] = true,
              },
            }
            assert.truthy(ok, res)
            assert.matches("x%-ratelimit%-limit%-video%-second: %d+", res)
            assert.matches("x%-ratelimit%-remaining%-video%-second: %d+", res)

            -- Note: tests for this plugin rely on the ability to manipulate
            -- upstream response headers, which is not currently possible with
            -- the grpc service we use. Therefore, we are only testing that
            -- headers are indeed inserted.
          end)

          it("blocks if exceeding limit #brian2", function()
            wait_server_sync({ Host = "test1.test" })
            test_limit("/response-headers", {["x-kong-limit"] = "video=1"}, "test1.test")
          end)

          it("counts against the same service register from different routes", function()
            wait_server_sync( { Host = "test1.test" })
            local n = math.floor(ITERATIONS / 2)
            local url = "/response-headers?x-kong-limit=" .. escape_uri("video=1, test=" .. ITERATIONS)
            for i = 1, n do
              local res = proxy_client():get(url , {
                headers = { Host = "test-service1.test" },
              })
              assert.res_status(200, res)
            end

            for i = n+1, ITERATIONS do
              local res = proxy_client():get(url, {
                headers = { Host = "test-service2.test" },
              })
              assert.res_status(200, res)
            end

            wait_remaining_sync("/response-headers", { Host = "test-service1.test" }, {["x-ratelimit-remaining-video-second"] = 0})

            -- Additional request, while limit is ITERATIONS/second
            local res = proxy_client():get(url, {
              headers = { Host = "test-service1.test" },
            })
            assert.res_status(429, res)
          end)

          it("handles multiple limits", function()
            wait_server_sync( { Host = "test1.test" })
            local n = math.floor(ITERATIONS / 2)
            local res
            local url = "/response-headers?x-kong-limit=" .. escape_uri("video=2, image=1")
            local remain_in_sec = ITERATIONS * 2
            local remain_in_min = ITERATIONS * 4
            for i = 1, n do
              res = proxy_client():get(url, {
                headers = { Host = "test2.test" },
              })
              assert.res_status(200, res)
              remain_in_sec = remain_in_sec - 2
              remain_in_min = remain_in_min - 2
            end
            res = wait_remaining_sync("/response-headers",
              { Host = "test2.test" },
              {["x-ratelimit-remaining-video-second"] = remain_in_sec, ["x-ratelimit-remaining-video-minute"] = remain_in_min}
            )

            assert.equal(ITERATIONS * 2, tonumber(res.headers["x-ratelimit-limit-video-second"]))
            assert.equal(remain_in_sec, tonumber(res.headers["x-ratelimit-remaining-video-second"]))
            assert.equal(ITERATIONS * 4, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
            assert.equal(remain_in_min, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
            assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-image-second"]))
            assert.equal(ITERATIONS - n, tonumber(res.headers["x-ratelimit-remaining-image-second"]))

            url = "/response-headers?x-kong-limit=" .. escape_uri("video=1, image=1")
            for i = n+1, ITERATIONS do
              res = proxy_client():get(url, {
                headers = { Host = "test2.test" },
              })
              assert.res_status(200, res)
              remain_in_sec = remain_in_sec - 1
              remain_in_min = remain_in_min - 1
            end
            res = wait_remaining_sync("/response-headers",
              { Host = "test2.test" }, 
              {["x-ratelimit-remaining-video-second"] = remain_in_sec, ["x-ratelimit-remaining-video-minute"] = remain_in_min})

            assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-image-second"]))
            assert.equal(remain_in_min, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
            assert.equal(remain_in_sec, tonumber(res.headers["x-ratelimit-remaining-video-second"]))


            local res = proxy_client():get(url, {
              headers = { Host = "test2.test" },
            })
            remain_in_sec = remain_in_sec - 1
            remain_in_min = remain_in_min - 1

            assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-image-second"]))
            assert.equal(remain_in_min, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
            assert.equal(remain_in_sec, tonumber(res.headers["x-ratelimit-remaining-video-second"]))
            assert.res_status(429, res)
          end)
        end)

        describe("With authentication", function()
          describe("API-specific plugin", function()
            it("blocks if exceeding limit and a per consumer & route setting", function()
              wait_server_sync({ Host = "test3.test" }, "apikey123")
              test_limit("/response-headers", {["apikey"] = "apikey123", ["x-kong-limit"] = "video=1"}, "test3.test", ITERATIONS - 2)
            end)

            it("blocks if exceeding limit and a per route setting", function()
              wait_server_sync({ Host = "test3.test" }, "apikey123")
              test_limit("/response-headers", {["apikey"] = "apikey124", ["x-kong-limit"] = "video=1"}, "test3.test", ITERATIONS - 3)
            end)
          end)
        end)

        describe("Upstream usage headers #brian", function()
          it("should append the headers with multiple limits", function()
            wait_server_sync( { Host = "test8.test" })
            local res = proxy_client():get("/get", {
              headers = { Host = "test8.test" },
            })
            local json = cjson.decode(assert.res_status(200, res))
            assert.equal(ITERATIONS-1, tonumber(json.headers["x-ratelimit-remaining-image"]))
            assert.equal(ITERATIONS, tonumber(json.headers["x-ratelimit-remaining-video"]))

            -- Actually consume the limits
            res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=2, image=1"), {
              headers = { Host = "test8.test" },
            })
            local json2 = cjson.decode(assert.res_status(200, res))
            assert.equal(ITERATIONS-1, tonumber(json2.headers["x-ratelimit-remaining-image"]))
            assert.equal(ITERATIONS, tonumber(json2.headers["x-ratelimit-remaining-video"]))

            wait_remaining_sync("/response-headers", { Host = "test8.test" }, {["x-ratelimit-remaining-video-second"] =ITERATIONS - 2})

            local res = proxy_client():get("/get", {
              headers = { Host = "test8.test" },
            })
            local body = cjson.decode(assert.res_status(200, res))
            assert.equal(ITERATIONS-2, tonumber(body.headers["x-ratelimit-remaining-image"]))
            assert.equal(ITERATIONS-2, tonumber(body.headers["x-ratelimit-remaining-video"]))
          end)

          it("combines multiple x-kong-limit headers from upstream", function()
            wait_server_sync( { Host = "test4.test" })
            -- NOTE: this test is not working as intended because multiple response headers are merged into one comma-joined header by send_text_response function
            for _ = 1, ITERATIONS do
              local res = proxy_client():get("/response-headers?x-kong-limit=video%3D2&x-kong-limit=image%3D1", {
                headers = { Host = "test4.test" },
              })
              assert.res_status(200, res)
            end

            proxy_client():get("/response-headers?x-kong-limit=video%3D1", {
              headers = { Host = "test4.test" },
            })

            wait_remaining_sync("/response-headers", { Host = "test4.test" }, {["x-ratelimit-remaining-video-second"] = 1})

            local res = proxy_client():get("/response-headers?x-kong-limit=video%3D2&x-kong-limit=image%3D1", {
              headers = { Host = "test4.test" },
            })

            assert.res_status(429, res)
            assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-image-second"]))
            assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-video-second"]))
          end)
        end)

        it("should block on first violation", function()
          wait_server_sync( { Host = "test7.test" })
          local res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=2, image=4"), {
            headers = { Host = "test7.test" },
          })
          assert.res_status(200, res)
          wait_remaining_sync("/response-headers", { Host = "test7.test" }, {["x-ratelimit-remaining-video-second"] = ITERATIONS}, 429)

          res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=2"), {
            headers = { Host = "test7.test" },
          })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.matches("API rate limit exceeded for 'image'", json.message)
        end)

        describe("Config with hide_client_headers", function()
          it("does not send rate-limit headers when hide_client_headers==true", function()
            wait_server_sync( { Host = "test9.test" })
            local res = proxy_client():get("/status/200", {
              headers = { Host = "test9.test" },
            })

            assert.res_status(200, res)
            assert.is_nil(res.headers["x-ratelimit-remaining-video-second"])
            assert.is_nil(res.headers["x-ratelimit-limit-video-second"])
          end)
        end)
      end)

      describe(fmt("Plugin: response-ratelimiting (expirations) with policy: #%s #%s [#%s]", redis_conf_name, policy, strategy), function()

        lazy_setup(function()
          local bp = init_db(strategy, policy)

          local route = bp.routes:insert {
            hosts      = { "expire1.test" },
            protocols  = { "http", "https" },
          }

          bp.response_ratelimiting_plugins:insert {
            route = { id = route.id },
            config   = {
              policy            = policy,
              redis = {
                host        = REDIS_HOST,
                port        = redis_conf.redis_port,
                ssl         = redis_conf.redis_ssl,
                ssl_verify  = redis_conf.redis_ssl_verify,
                server_name = redis_conf.redis_server_name,
                password    = REDIS_PASSWORD,
              },
              fault_tolerant    = false,
              limits            = { video = { second = ITERATIONS } },
            }
          }

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            lua_ssl_trusted_certificate = "spec/fixtures/redis/ca.crt",
          }))
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        it("expires a counter", function()
          wait_server_sync( { Host = "expire1.test" })
          local res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=1"), {
            headers = { Host = "expire1.test" },
          })

          assert.res_status(200, res)
          assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-video-second"]))
          assert.equal(ITERATIONS-1, tonumber(res.headers["x-ratelimit-remaining-video-second"]))

          wait_server_sync( { Host = "expire1.test" }) -- Wait for counter to expire

          res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=1"), {
            headers = { Host = "expire1.test" },
          })

          assert.res_status(200, res)
          assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-video-second"]))
          assert.equal(ITERATIONS-1, tonumber(res.headers["x-ratelimit-remaining-video-second"]))
        end)
      end)

      describe(fmt("Plugin: response-ratelimiting (access - global for single consumer) with policy: #%s  #%s [#%s]", redis_conf_name, policy, strategy), function()

        lazy_setup(function()
          local bp = init_db(strategy, policy)

          local consumer = bp.consumers:insert {
            custom_id = "provider_126",
          }

          bp.key_auth_plugins:insert()

          bp.keyauth_credentials:insert {
            key      = "apikey126",
            consumer = { id = consumer.id },
          }

          -- just consumer, no no route or service
          bp.response_ratelimiting_plugins:insert({
            consumer = { id = consumer.id },
            config = {
              fault_tolerant    = false,
              policy            = policy,
              redis = {
                host        = REDIS_HOST,
                port        = redis_conf.redis_port,
                ssl         = redis_conf.redis_ssl,
                ssl_verify  = redis_conf.redis_ssl_verify,
                server_name = redis_conf.redis_server_name,
                password    = REDIS_PASSWORD,
                database    = REDIS_DATABASE,
              },
              limits            = { video = { second = ITERATIONS } },
            }
          })

          for i = 1, ITERATIONS do
            bp.routes:insert({ hosts = { fmt("test%d.test", i) } })
          end

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            lua_ssl_trusted_certificate = "spec/fixtures/redis/ca.crt",
          }))
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        it("blocks when the consumer exceeds their quota, no matter what service/route used", function()
          wait_server_sync({ Host = "test1.test" }, "apikey126")
          test_limit("/response-headers", {["apikey"] = "apikey126", ["x-kong-limit"] = "video=1"}, "test%d.test")
        end)
      end)

      describe(fmt("Plugin: response-ratelimiting (access - global) with policy: #%s #%s [#%s]", redis_conf_name, policy, strategy), function()

        lazy_setup(function()
          local bp = init_db(strategy, policy)

          -- global plugin (not attached to route, service or consumer)
          bp.response_ratelimiting_plugins:insert({
            config = {
              fault_tolerant = false,
              policy            = policy,
              redis = {
                host        = REDIS_HOST,
                port        = redis_conf.redis_port,
                ssl         = redis_conf.redis_ssl,
                ssl_verify  = redis_conf.redis_ssl_verify,
                server_name = redis_conf.redis_server_name,
                password    = REDIS_PASSWORD,
                database    = REDIS_DATABASE,
              },
              limits            = { video = { second = ITERATIONS } },
            }
          })

          for i = 1, ITERATIONS do
            bp.routes:insert({ hosts = { fmt("test%d.test", i) } })
          end

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            lua_ssl_trusted_certificate = "spec/fixtures/redis/ca.crt",
          }))
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        before_each(function()
          wait_server_sync({ Host = "test1.test" })
        end)

        it("blocks if exceeding limit", function()
          for i = 1, ITERATIONS do
            local res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=1"), {
              headers = { Host = fmt("test%d.test", i) },
            })
            assert.res_status(200, res)
          end

          -- Wait for async timer to increment the limit
          wait_remaining_sync("/response-headers", { Host = "test1.test" }, {["x-ratelimit-remaining-video-second"] = 0})

          -- last query, while limit is ITERATIONS/second
          local res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=1"), {
            headers = { Host = "test1.test" },
          })
          assert.res_status(429, res)
          assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-video-second"]))
          assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-video-second"]))
        end)
      end)

      describe(fmt("Plugin: response-ratelimiting (fault tolerance) with policy: #%s #%s [#%s]", redis_conf_name, policy, strategy), function()
        if policy == "cluster" then
          local bp, db

          pending("fault tolerance tests for cluster policy temporarily disabled", function()

            before_each(function()
              bp, db = init_db(strategy, policy)

              local route1 = bp.routes:insert {
                hosts = { "failtest1.test" },
              }

              bp.response_ratelimiting_plugins:insert {
                route = { id = route1.id },
                config   = {
                  fault_tolerant    = false,
                  policy            = policy,
                  redis = {
                    host        = REDIS_HOST,
                    port        = redis_conf.redis_port,
                    ssl         = redis_conf.redis_ssl,
                    ssl_verify  = redis_conf.redis_ssl_verify,
                    server_name = redis_conf.redis_server_name,
                    password    = REDIS_PASSWORD,
                  },
                  limits            = { video = { second = ITERATIONS} },
                }
              }

              local route2 = bp.routes:insert {
                hosts = { "failtest2.test" },
              }

              bp.response_ratelimiting_plugins:insert {
                route = { id = route2.id },
                config   = {
                  fault_tolerant    = true,
                  policy            = policy,
                  redis = {
                    host        = REDIS_HOST,
                    port        = redis_conf.redis_port,
                    ssl         = redis_conf.redis_ssl,
                    ssl_verify  = redis_conf.redis_ssl_verify,
                    server_name = redis_conf.redis_server_name,
                    password    = REDIS_PASSWORD,
                  },
                  limits            = { video = {second = ITERATIONS} }
                }
              }

              assert(helpers.start_kong({
                database   = strategy,
                nginx_conf = "spec/fixtures/custom_nginx.template",
                lua_ssl_trusted_certificate = "spec/fixtures/redis/ca.crt",
              }))

            end)

            after_each(function()
              helpers.stop_kong()
            end)

            it("does not work if an error occurs", function()
              local res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=1"), {
                headers = { Host = "failtest1.test" },
              })
              assert.res_status(200, res)
              assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-video-second"]))
              assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-remaining-video-second"]))

              -- Simulate an error on the database
              -- (valid SQL and CQL)
              db.connector:query("DROP TABLE response_ratelimiting_metrics;")
              -- FIXME this leaves the database in a bad state after this test,
              -- affecting subsequent tests.

              -- Make another request
              res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=1"), {
                headers = { Host = "failtest1.test" },
              })
              local body = assert.res_status(500, res)
              local json = cjson.decode(body)
              assert.matches("An unexpected error occurred", json.message)
            end)

            it("keeps working if an error occurs", function()
              local res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=1"), {
                headers = { Host = "failtest2.test" },
              })
              assert.res_status(200, res)
              assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-video-second"]))
              assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-remaining-video-second"]))

              -- Simulate an error on the database
              -- (valid SQL and CQL)
              db.connector:query("DROP TABLE response_ratelimiting_metrics;")
              -- FIXME this leaves the database in a bad state after this test,
              -- affecting subsequent tests.

              -- Make another request
              res = proxy_client():get("/response-headers?x-kong-limit="..escape_uri("video=1"), {
                headers = { Host = "failtest2.test" },
              })
              assert.res_status(200, res)
              assert.is_nil(res.headers["x-ratelimit-limit-video-second"])
              assert.is_nil(res.headers["x-ratelimit-remaining-video-second"])
            end)
          end)
        end

        if policy == "redis" then

          before_each(function()
            local bp = init_db(strategy, policy)

            local route1 = bp.routes:insert {
              hosts      = { "failtest3.test" },
              protocols  = { "http", "https" },
            }

            bp.response_ratelimiting_plugins:insert {
              route = { id = route1.id },
              config   = {
                fault_tolerant = false,
                policy         = policy,
                redis = {
                  host = "5.5.5.5",
                  port = REDIS_PORT
                },
                limits         = { video = { second = ITERATIONS } },
              }
            }

            local route2 = bp.routes:insert {
              hosts      = { "failtest4.test" },
              protocols  = { "http", "https" },
            }

            bp.response_ratelimiting_plugins:insert {
              route = { id = route2.id },
              config   = {
                fault_tolerant = true,
                policy         = policy,
                redis = {
                  host = "5.5.5.5",
                  port = REDIS_PORT
                },
                limits         = { video = { second = ITERATIONS } },
              }
            }

            assert(helpers.start_kong({
              database   = strategy,
              nginx_conf = "spec/fixtures/custom_nginx.template",
              lua_ssl_trusted_certificate = "spec/fixtures/redis/ca.crt",
            }))

          end)

          after_each(function()
            helpers.stop_kong()
          end)

          it("does not work if an error occurs", function()
            -- Make another request
            local res = proxy_client():get("/status/200", {
              headers = { Host = "failtest3.test" },
            })
            local body = assert.res_status(500, res)
            local json = cjson.decode(body)
            assert.matches("An unexpected error occurred", json.message)
          end)
          it("keeps working if an error occurs", function()
            -- Make another request
            local res = proxy_client():get("/status/200", {
              headers = { Host = "failtest4.test" },
            })
            assert.res_status(200, res)
            assert.falsy(res.headers["x-ratelimit-limit-video-second"])
            assert.falsy(res.headers["x-ratelimit-remaining-video-second"])
          end)
        end
      end)

      ::continue::
    end
  end
end
