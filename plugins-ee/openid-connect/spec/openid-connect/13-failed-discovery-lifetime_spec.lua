-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"
local jws = require "kong.openid-connect.jws"
local json = require "cjson.safe"

local PLUGIN_NAME = "openid-connect"

local REDISCOVERY_LIFETIME = 10
local FAILURE_REDISCOVERY_LIFETIME = 5

local function sign_token(encoded_key)
  local now = ngx.time()
  local exp = now + 600
  local jwk = json.decode(encoded_key)
  local token = {
    jwk = jwk,
    header = {
      typ = "JWT",
      alg = jwk.alg,
    },
    payload = {
      sub = "1234567890",
      name = "John Doe",
      exp = exp,
      now = now,
    },
  }

  return assert(jws.encode(token))
end

for _, strategy in helpers.all_strategies() do
  describe("failed discovery lifetime: #" .. strategy, function()
    local proxy_client
    local HTTP_SERVER_PORT = helpers.get_available_port()
    local good_issuer = "http://localhost:" .. HTTP_SERVER_PORT .. "/good_issuer"
    local bad_issuer = "http://localhost:" .. HTTP_SERVER_PORT .. "/bad_issuer"
    local ec_key = '{"kty":"EC","crv":"P-256","y":"kGe5DgSIycKp8w9aJmoHhB1sB3QTugfnRWm5nU_TzsY","alg":"ES256","kid":"19J8y7Zprt2-QKLjF2I5pVk0OELX6cY2AfaAv1LC_w8","x":"EVs_o5-uQbTjL3chynL4wXgUg2R9q9UU8I5mEovUf84","d":"evZzL1gdAFr88hb2OF_2NxApJCzGCEDdfSp6VQO30hw"}'
    local unknown_key = [[{
    "p": "9ateOx8okTBeuC6-Vn1UxvgywJmHjisNw6xCdaw6G3SBdawazo907etSNnIiTau2fIH5lzdjdy4lb8A5Hj0x_P-d3rOlAW8CLdh9x1ZvVSPI3Xi96CCM9K9FbWe8pcXBQ95k6TCBuhyuUwmdhCM4Dot8zabFpZgvmcWiFUgGpNc",
    "kty": "RSA",
    "q": "7NRhfB0L9nClkouXVSiFYEORH3-y65MjTDe-EibkBY5gFAlsMP-R8Wyi4Rm-Dvgi6CG4win9X4PHkdHtKyemWNOmibr9OFoA9D6_GgXjcy0jy0IJOeN6f7gZo2sJk3OmrEhGmoOSnvfo9Vwym3zslqCs2TIeBF8rYI8_oGKCJyU",
    "d": "x0l8SZuwpYTUYhQppcpEOnPW3_WQUtyG3c7Zo5nn3Z-eDZlYKwrhjEdNS4mt1s5spgiuczg0OQtY4p1X5ddmIkFpOsPsNI4mBYAo73Mr5XntvenFM9jefd3XDiy_qRkmBZzwDCETcp4KuEnsI9XVHR3evPFwORYOBFHAzaS0WFeaoI3toOfZ2gHXHg54yswymJotOxAMoqgk7GUcv0F4d8MyEu95GFp9NeGZA1BTsmNogAHR5WfvrDAwQEAf8WpYa7ihQbP2ViZlZ9zg1-ZQBwxSiktL2kE083hKKgtxfDbXop9pxP15tp_8dfysQJa_TfDnXXviwGtYZeC2L9kjiQ",
    "e": "AQAB",
    "kid": "Le_uhxiylkaRlqp2i8xhpTqXCJVwvCx47bAg7KYIWYE",
    "qi": "sxe63q2IKiOGIDQd333GjzkXOCT94Zc6JizkiKNYO2gph9pHlJ9G5eBsty9AMLkUwDvPKx1i3B7-imPwB1Hijzagqva5xSfbepqG0ndoUGKZY64uU4ZAWdWq_f5N06Dim1zwXV2aJb1k-4Wh4JCvcLa1b7ep8w5ldDfCGrMnLNA",
    "dp": "zbLRUbuDIh5YEOvCn3SNeZP0GuPyZo2SFtazRwgQF1Dz3O1f_LiNdXDmA4SJSHOQdqv1qjHMbMwMuIdAzBr9MhNtwjy02oByWKS-nBu5WJZ_50Dj8erfWzkubq6_fCYa7pLV95KP7J97LzgL1coPc85Dj4YmU8MbiCu8zQjj1z0",
    "alg": "RS256",
    "dq": "F_ZZMryhpDq7lftHwZcK_7V2bpB2Iv3NOX3-XknPEnzYXc6iQsbpFltek5YOM-eJaKFY11R2TX7A55EtBQvK-fvYQuFHk7cPl6btoQ1teQ7dK0iwNEo-78NJ3M4Mtv2hpJbfhezAHhOJX6IHgNIAAjGZq5Q1k02pzuhPkMPG1X0",
    "n": "40XKVZNFI2rPhfFcTB8-3SjsMFzNXW7Paes6xfUQ0suo8TG6JIQBVSo06HqZrnPvty4T0rdT1tGM2pzKfZfyQEwscPEDn7L_g0uKcmOYkGUVUK-1XR4X3OFgucLqfw-5ybXDzbPChfprcxdAS0aiTIliHDMAwVPfxrF9iTwUtdTXxK3tyFlEUmKLr7DCmY6bc7hRro-nMpxP8pZG5y_tx0eYVslcS-fTUmkPvupwQwj10ipXYZdjHhqWwd_wPmpWnA42Kp2KHiwQ0ijZvNOvKpNCfeheyiUFi9_eQBHCo0Yt8ddvdoMBsUMyGOKEp9K2nIQyDOUbumEkc7jmb0CUEw"
}]]

    local mock = http_mock.new(HTTP_SERVER_PORT, {
      ["/good_issuer/.well-known/openid-configuration"] = {
        access = [[
          ngx.header.content_type = "application/json"
          local json = '{ "issuer": "]] .. good_issuer .. [[", "jwks": [ ]] .. ec_key .. [[ ] }'
          ngx.print(json)
          ngx.exit(200)
        ]]
      },

      ["/bad_issuer/.well-known/openid-configuration"] = {
        access = [[
          ngx.exit(500)
        ]]
      }
    })

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        PLUGIN_NAME,
      })

      local service = bp.services:insert {
        name = PLUGIN_NAME,
        path = "/anything"
      }

      local bad_route = bp.routes:insert {
        service = service,
        paths   = { "/bad" },
      }

      local good_route = bp.routes:insert {
        service = service,
        paths   = { "/good" },
      }

      bp.plugins:insert {
        route   = bad_route,
        name    = PLUGIN_NAME,
        config  = {
          issuer    = bad_issuer,
          auth_methods = {
            "bearer",
          },
          rediscovery_lifetime = REDISCOVERY_LIFETIME,
        },
      }

      bp.plugins:insert {
        route   = good_route,
        name    = PLUGIN_NAME,
        config  = {
          issuer    = good_issuer,
          auth_methods = {
            "bearer",
          },
          rediscovery_lifetime = REDISCOVERY_LIFETIME,
        },
      }

      assert(mock:start())
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins    = "bundled," .. PLUGIN_NAME,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      mock:stop()
    end)

    it("use a short lifetime if the last discovery failed", function()

      -- send a request first in case the first discovery hasn't been done yet
      proxy_client = assert(helpers.proxy_client())
      local res = assert(proxy_client:send({
        method = "GET",
        path = "/bad",
        headers = {
          ["Authorization"] = "Bearer " .. sign_token(ec_key),
        },
      }))
      assert.response(res).has.status(401)
      proxy_client:close()

      helpers.clean_logfile()

      proxy_client = assert(helpers.proxy_client())
      res = assert(proxy_client:send({
        method = "GET",
        path = "/bad",
        headers = {
          ["Authorization"] = "Bearer " .. sign_token(ec_key),
        },
      }))
      assert.response(res).has.status(401)
      proxy_client:close()

      assert.logfile().has.line("the last discovery failed, use a short rediscovery lifetime", true, 0)

      -- wait FAILURE_REDISCOVERY_LIFETIME sencods so that it will load configuration using discovery
      ngx.sleep(FAILURE_REDISCOVERY_LIFETIME + 1)
      helpers.clean_logfile()

      proxy_client = assert(helpers.proxy_client())
      res = assert(proxy_client:send({
        method = "GET",
        path = "/bad",
        headers = {
          ["Authorization"] = "Bearer " .. sign_token(ec_key),
        },
      }))
      assert.response(res).has.status(401)
      proxy_client:close()

      assert.logfile().has.line("the last discovery failed, use a short rediscovery lifetime", true, 0)
      assert.logfile().has.line("loading configuration for " .. bad_issuer .. " using discovery", true)
    end)

    it("doesn't use a short lifetime if the last discovery succeeded", function()
      -- send a request first in case the first discovery hasn't been done yet
      proxy_client = assert(helpers.proxy_client())
      local res = assert(proxy_client:send({
        method = "GET",
        path = "/good",
        headers = {
          ["Authorization"] = "Bearer " .. sign_token(ec_key),
        },
      }))
      assert.response(res).has.status(200)
      proxy_client:close()

      helpers.clean_logfile()

      proxy_client = assert(helpers.proxy_client())
      res = assert(proxy_client:send({
        method = "GET",
        path = "/good",
        headers = {
          -- use a unknown key so it will try to rediscover everytime
          ["Authorization"] = "Bearer " .. sign_token(unknown_key),
        },
      }))
      assert.response(res).has.status(401)
      proxy_client:close()
      assert.logfile().has.no.line("the last discovery failed, use a short rediscovery lifetime", true, 0)
    end)
  end)
end

