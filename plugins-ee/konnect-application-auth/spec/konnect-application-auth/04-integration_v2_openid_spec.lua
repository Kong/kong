-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- local cjson = require "cjson.safe"
local helpers = require "spec.helpers"
local uuid = require("kong.tools.utils").uuid
-- local http_mock = require "spec.helpers.http_mock"
local sub = string.sub

local encode_base64 = ngx.encode_base64

local PLUGIN_NAME = "konnect-application-auth"
local OIDC_PLUGIN_NAME = "openid-connect"

local KEYCLOAK_HOST = os.getenv("KONG_SPEC_TEST_KEYCLOAK_HOST") or "keycloak"
local KEYCLOAK_PORT = tonumber(os.getenv("KONG_SPEC_TEST_KEYCLOAK_PORT_8080")) or 8080
local REALM_PATH = "/realms/demo"
local DISCOVERY_PATH = "/.well-known/openid-configuration"
local ISSUER_URL = "http://" .. KEYCLOAK_HOST .. ":" .. KEYCLOAK_PORT .. REALM_PATH

local CLIENT_ID = "service"
local CLIENT_SECRET = "7adf1a21-6b9e-45f5-a033-d0e8f47b1dbc"
local CLIENT_CREDENTIALS = "Basic " .. encode_base64(CLIENT_ID .. ":" .. CLIENT_SECRET)

local host_client_credentials = "client_credentials.konghq.com"
local host_bearer = "bearer.konghq.com"
local host_all = "all.konghq.com"
local host_all_session_secret = "all_secret.konghq.com"


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (integration v2 openid) [#" .. strategy .. "]", function()
    local proxy_client
    lazy_setup(function()
      local bp, db = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, {
        "konnect_applications", "services", "plugins",
      }, { PLUGIN_NAME, "ctx-checker", OIDC_PLUGIN_NAME })

      local strat_all_id = uuid()
      local scope = uuid()

      local client_credentials_service = bp.services:insert({
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      })
      local all_service_session_secret = bp.services:insert({
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      })
      local all_service = bp.services:insert({
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      })
      bp.routes:insert({
          service = client_credentials_service,
          hosts = { host_client_credentials }
      })
      bp.routes:insert({
        service = client_credentials_service,
        hosts = { host_bearer }
      })
      bp.routes:insert({
        service = all_service,
        hosts = { host_all }
      })
      bp.routes:insert({
        service = all_service_session_secret,
        hosts = { host_all_session_secret }
      })
      bp.plugins:insert({
        name = PLUGIN_NAME,
        service = all_service,
        config = {
          scope = scope,
          auth_type = "v2-strategies",
          v2_strategies = {
            openid_connect = {
              {
                strategy_id = strat_all_id,
                config = {
                  issuer = ISSUER_URL,
                  auth_methods = {
                    "client_credentials",
                    "bearer",
                    "session",
                  },
                  credential_claim = {
                    "azp",
                  },
                }
              }
            }
          }
        }
      })
      bp.plugins:insert({
        name = PLUGIN_NAME,
        service = all_service_session_secret,
        config = {
          scope = scope,
          auth_type = "v2-strategies",
          v2_strategies = {
            openid_connect = {
              {
                strategy_id = strat_all_id,
                config = {
                  issuer = ISSUER_URL,
                  auth_methods = {
                    "client_credentials",
                    "bearer",
                    "session",
                  },
                  credential_claim = {
                    "azp",
                  },
                  session_secret = "$€CR€T",
                }
              }
            }
          }
        }
      })
      db.konnect_applications:insert({
        client_id = CLIENT_ID,
        scopes = { scope },
        auth_strategy_id = strat_all_id
      })

      -- start kong
      assert(helpers.start_kong({
      -- set the strategy
      database   = strategy,
      -- use the custom test template to create a local mock server
      nginx_conf = "spec/fixtures/custom_nginx.template",
      -- make sure our plugin gets loaded
      plugins = "bundled," .. PLUGIN_NAME ..",".. OIDC_PLUGIN_NAME,
      -- write & load declarative config, only if 'strategy=off'
      declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,

      }))
    end)
    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)
    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
    end)
    describe("setup",function()
      it("can access openid connect discovery endpoint on demo realm with http", function()
        local client = helpers.http_client(KEYCLOAK_HOST, KEYCLOAK_PORT)
        local res = client:get(REALM_PATH .. DISCOVERY_PATH)
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal(ISSUER_URL, json.issuer)
      end)
    end)
    describe("authentication",function()
      describe("all",function()
        describe("client_credentials",function()
          it("is protected", function()
            local res = proxy_client:get("/", {
              headers = {
                Authorization = "Basic 1234",
                host = host_all,
              },
            })

            assert.response(res).has.status(401)
          end)
          it("is allowed with valid credentials Authorization Basic", function()
            local res = proxy_client:get("/", {
              headers = {
                Authorization = CLIENT_CREDENTIALS,
                host = host_all,
              },
            })

            assert.response(res).has.status(200)
            local json = assert.response(res).has.jsonbody()
            assert.is_not_nil(json.headers.authorization)
            assert.equal("Bearer", sub(json.headers.authorization, 1, 6))
          end)
        end)
        describe("bearer",function()
          it("is allowed with a bearer",function()
            local res = proxy_client:get("/", {
              headers = {
                Authorization = CLIENT_CREDENTIALS,
                host = host_all,
              },
            })

            assert.response(res).has.status(200)
            local json = assert.response(res).has.jsonbody()
            assert.is_not_nil(json.headers.authorization)
            assert.equal("Bearer", sub(json.headers.authorization, 1, 6))
            -- getting the bearer from a client credentials
            -- then reusing it as bearer
            local bearer = json.headers.authorization
            local res_bearer = proxy_client:get("/", {
              headers = {
                Authorization = bearer,
                host = host_all,
              },
            })
            assert.response(res_bearer).has.status(200)
          end)
          it("is protected", function()
            local res = proxy_client:get("/", {
              headers = {
                Authorization = "Bearer asdfasdfasdf",
                host = host_all,
              },
            })

            assert.response(res).has.status(401)
          end)
        end)
        describe("session",function()
          it("is protected", function()
            local res = proxy_client:get("/", {
              headers = {
                Cookie = "session=asdfasdfasdf",
                host = host_all,
              },
            })

            assert.response(res).has.status(401)
          end)
          it("is allowed with a session using issuer secret",function()
            local res = proxy_client:get("/", {
              headers = {
                Authorization = CLIENT_CREDENTIALS,
                host = host_all,
              },
            })

            assert.response(res).has.status(200)
            assert.is_not_nil(res.headers["Set-Cookie"])
            assert.equal("session=", sub(res.headers["Set-Cookie"], 1, 8))
            local cookie = res.headers["Set-Cookie"]
            local res_bearer = proxy_client:get("/", {
              headers = {
                Cookie = cookie,
                host = host_all,
              },
            })
            assert.response(res_bearer).has.status(200)
          end)
          it("is allowed with a session using plugin secret",function()
            local res = proxy_client:get("/", {
              headers = {
                Authorization = CLIENT_CREDENTIALS,
                host = host_all_session_secret,
              },
            })

            assert.response(res).has.status(200)
            assert.is_not_nil(res.headers["Set-Cookie"])
            assert.equal("session=", sub(res.headers["Set-Cookie"], 1, 8))
            local cookie = res.headers["Set-Cookie"]
            local res_bearer = proxy_client:get("/", {
              headers = {
                Cookie = cookie,
                host = host_all_session_secret,
              },
            })
            assert.response(res_bearer).has.status(200)
          end)
        end)
      end)
    end)
  end)
end
