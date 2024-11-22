-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers      = require "spec.helpers"
local redis        = require "resty.redis"


local str_fmt     = string.format
local math_foor   = math.floor
local ngx_time    = ngx.time
local update_time = ngx.update_time


local DEFAULT_TIMEOUT         = 2000
local REDIS_AUTH_HOST         = "localhost" -- "localhost" on CI; "proxy" in local dev
local REDIS_AUTH_PORT         = 1999
local BACKEND_REDIS_AUTH_HOST = "localhost" -- "localhost" on CI; "redis-ssl-auth" in local dev
local BACKEND_REDIS_AUTH_PORT = 7379 -- "7379" on CI; "6379" in local dev
local REDIS_USERNAME          = "default"
local REDIS_PASSWORD          = "kong"
local PLUGIN_NAME             = "rate-limiting-advanced"
local MOCK_UPSTREAM_URL       = helpers.mock_upstream_url


local function get_red(host, port, username, password)
  local red = assert(redis:new())
  red:set_timeout(DEFAULT_TIMEOUT)
  assert(red:connect(host, port))
  if password then
    if username then
      assert(red:auth(username, password))

    else
      assert(red:auth(password))
    end
  end

  return red
end


for _, strategy in helpers.all_strategies() do
  describe("Connect to Redis via Envoy proxy [#" .. strategy .. "]", function ()
    local window1 = 60
    local sync_rate = 0.1
    local namespace = "ice"

    lazy_setup(function()
      local bp = helpers.get_db_utils(
        strategy == "off" and "postgres" or strategy,
        { "routes", "services", "plugins" },
        { PLUGIN_NAME, "key-auth" })

      local con1 = assert(bp.consumers:insert {
        username      = "alice",
        custom_id = "alice_123"
      })
      assert(bp.keyauth_credentials:insert {
        key      = "foo-key",
        consumer = { id = con1.id }
      })

      local srv1 = assert(bp.services:insert {
        name     = "srv1",
        url      = MOCK_UPSTREAM_URL
      })

      local rt1 = assert(bp.routes:insert {
        name = "rt1",
        paths = { "/rla1" },
        service = { id = srv1.id }
      })

      assert(bp.plugins:insert {
        name   = "key-auth",
        route  = { id = rt1.id },
        config = {
          key_names = { "apikey" }
        }
      })

      assert(bp.plugins:insert {
        name   = PLUGIN_NAME,
        route  = { id = rt1.id },
        config = {
          namespace   = namespace,
          window_size = { window1 },
          limit       = { 5 },
          identifier  = "consumer",
          sync_rate   = sync_rate,
          strategy    = "redis",
          redis       = {
            connection_is_proxied = true,
            host                  = REDIS_AUTH_HOST,
            port                  = REDIS_AUTH_PORT,
            username              = REDIS_USERNAME,
            password              = REDIS_PASSWORD,
            redis_proxy_type      = "envoy_v1.31",
          }
        }
      })

      local declarative_config = helpers.make_yaml_file(str_fmt([=[
        _format_version: '3.0'
        _transform: true
        services:
        - name: srv1
          url: %s
          routes:
          - name: rt1
            paths:
            - /rla1
            plugins:
            - name: key-auth
              config:
                key_names:
                - apikey
            - name: %s
              config:
                namespace: %s
                window_size:
                - %s
                limit:
                - 5
                identifier: consumer
                sync_rate: %s
                strategy: redis
                redis:
                  connection_is_proxied: true
                  host: %s
                  port: %s
                  username: %s
                  password: %s
                  redis_proxy_type: %s
        consumers:
        - username: alcie
          custom_id: alice_123
          keyauth_credentials:
          - key: foo-key
      ]=], MOCK_UPSTREAM_URL, PLUGIN_NAME, namespace, window1, sync_rate,
      REDIS_AUTH_HOST, REDIS_AUTH_PORT, REDIS_USERNAME, REDIS_PASSWORD, "envoy_v1.31"))

      assert(helpers.start_kong({
        database = strategy,
        plugins = PLUGIN_NAME .. "," .. "key-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = strategy == "off" and declarative_config or nil,
        pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
        nginx_worker_processes = 1,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("support client side authentication", function()
      local red = get_red(BACKEND_REDIS_AUTH_HOST, BACKEND_REDIS_AUTH_PORT,
                          REDIS_USERNAME, REDIS_PASSWORD)
      assert.is_not_nil(red)
      assert(red:flushall())

      local proxy_client = helpers.proxy_client()

      update_time()
      local window_start = math_foor(ngx_time()/window1) * window1
      local hash_key = window_start .. ":" .. window1 .. ":" .. namespace

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/rla1",
        headers = {
          apikey = "foo-key"
        }
      })

      assert.res_status(200, res)
      assert.are.same(5, tonumber(res.headers["x-ratelimit-limit-minute"]))
      assert.are.same(5, tonumber(res.headers["ratelimit-limit"]))
      assert.are.same(4, tonumber(res.headers["x-ratelimit-remaining-minute"]))
      assert.are.same(4, tonumber(res.headers["ratelimit-remaining"]))
      assert.is_true(tonumber(res.headers["ratelimit-reset"]) > 0)
      assert.is_nil(res.headers["retry-after"])

      assert
      .with_timeout(10)
      .with_max_tries(20)
      .with_step(sync_rate)
      .ignore_exceptions(true)
      .eventually(function()
        local rla_count = assert(red:hgetall(hash_key))
        local redis_res = assert(red:array_to_hash(rla_count))
        for k, v in pairs(redis_res) do
          assert.is_truthy(k)
          assert.are_equal('1', v)
        end
      end)
      .has_no_error("failed to sync with backend Redis")

      assert(red:flushall())
      red:close()
      proxy_client:close()
    end)

  end)
end
