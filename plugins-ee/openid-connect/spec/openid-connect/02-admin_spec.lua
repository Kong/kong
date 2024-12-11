-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson   = require "cjson"
local idp_conf = require "spec-ee.fixtures.keycloak_api".new().config


local str_fmt = string.format


local PLUGIN_NAME = "openid-connect"
local JWKS_URI = "/" .. PLUGIN_NAME .. "/jwks"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _ , strategy in strategies() do

describe(JWKS_URI .. "#" .. strategy, function()
  local admin_client

  lazy_setup(function()
    helpers.get_db_utils(strategy, nil, { PLUGIN_NAME })

    assert(helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled," .. PLUGIN_NAME,
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    admin_client = helpers.admin_client()
  end)

  after_each(function()
    if admin_client then
      admin_client:close()
    end
  end)

  it("returns public keys for all supported algorithms", function()
    local res = admin_client:get(JWKS_URI)
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.is_table(json)

    local algs = {}

    for _, jwk in ipairs(json.keys) do
      algs[jwk.alg] = true
    end

    assert.same({
      HS256 = true,
      HS384 = true,
      HS512 = true,
      RS256 = true,
      RS512 = true,
      PS256 = true,
      PS384 = true,
      PS512 = true,
      ES256 = true,
      ES384 = true,
      ES512 = true,
      EdDSA = true,
      RS384 = true,
    }, algs)
  end)

  it("removes private keys for all supported algorithms", function()
    local res = admin_client:get(JWKS_URI)
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.is_table(json)

    for _, jwk in ipairs(json.keys) do
      assert.equal(nil, jwk.k)
      assert.equal(nil, jwk.d)
      assert.equal(nil, jwk.p)
      assert.equal(nil, jwk.dp)
      assert.equal(nil, jwk.dq)
      assert.equal(nil, jwk.qi)
      assert.equal(nil, jwk.oth)
      assert.equal(nil, jwk.r)
      assert.equal(nil, jwk.t)
    end
  end)
end)

describe("skip issuer validation [#" .. strategy .. "]", function()
  local ISSUER_URL = idp_conf.issuer
  local KONG_CLIENT_ID = idp_conf.client_id
  local KONG_CLIENT_SECRET = idp_conf.client_secret

  local admin_client
  local proxy_client
  local rt

  lazy_setup(function()
    local bp = helpers.get_db_utils(
      strategy == "off" and "postgres" or strategy,
      {
        "services",
        "routes",
        "plugins",
      },
      {
        PLUGIN_NAME,
      }
    )

    local svc = bp.services:insert {
      path = "/anything"
    }

    rt = bp.routes:insert({
      service = { id = svc.id },
      hosts = { "test.oidc" },
    })

    assert(helpers.start_kong({
      database = strategy,
      plugins = PLUGIN_NAME,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
      nginx_worker_processes = 1,
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    admin_client = helpers.admin_client()
    proxy_client = helpers.proxy_client()
    helpers.clean_logfile()
  end)

  after_each(function()
    if admin_client then
      admin_client:close()
    end
    if proxy_client then
      proxy_client:close()
    end
  end)

  it("upon config loading or updating", function ()
    local res
    if strategy ~= "off" then
      res = admin_client:post("/plugins", {
        body = {
          name = PLUGIN_NAME,
          route = { id = rt.id },
          config  = {
            issuer    = ISSUER_URL,
            scopes = {
              -- this is the default
              "openid",
            },
            client_id = {
              KONG_CLIENT_ID,
            },
            client_secret = {
              KONG_CLIENT_SECRET,
            },
            upstream_refresh_token_header = "refresh_token",
            refresh_token_param_name      = "refresh_token",
            display_errors = true,
          },
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })

    else
      local declarative_config = str_fmt([=[
        _transform: true
        _format_version: '3.0'
        services:
        - url: %s
          routes:
          - hosts:
            - "test.oidc"
            plugins:
            - name: %s
              config:
                issuer: %s
                scopes:
                - openid
                client_id:
                - %s
                client_secret:
                - %s
                upstream_refresh_token_header: refresh_token
                refresh_token_param_name: refresh_token
                display_errors: true
      ]=], helpers.mock_upstream_url, PLUGIN_NAME, ISSUER_URL, KONG_CLIENT_ID, KONG_CLIENT_SECRET)

      res = admin_client:post("/config", {
        body = {
          config = declarative_config,
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
    end

    assert.res_status(201, res)
    assert.logfile().has.no.line("loading configuration for " .. ISSUER_URL .. " from database")
    assert.logfile().has.no.line("loading configuration for " .. ISSUER_URL .. " using discovery")
    assert.logfile().has.no.line("rediscovery for " .. ISSUER_URL .. " was done recently")
  end)

end)

end
