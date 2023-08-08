-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson.safe"
local resty_sha256 = require "resty.sha256"
local resty_str = require "resty.string"


local helpers = require "spec.helpers"
local uuid = require("kong.tools.utils").uuid


local PLUGIN_NAME = "konnect-application-auth"


local function hash_key(key)
  local sha256 = resty_sha256:new()
  sha256:update(key)
  return resty_str.to_hex(sha256:final())
end


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client
    local client_id = uuid()
    local forbidden_client_id_1 = uuid()
    local forbidden_client_id_2 = uuid()
    local forbidden_client_id_3 = uuid()
    local forbidden_client_id_4 = uuid()

    local scope = uuid()

    lazy_setup(function()

      local bp, db = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, {
        "konnect_applications", "services", "routes"
      }, { PLUGIN_NAME, "ctx-checker" })

      -- OIDC
      local oidc_service = bp.services:insert({
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      })

      bp.plugins:insert({
        name = PLUGIN_NAME,
        service = oidc_service,
        config = {
          scope = scope,
          auth_type = "openid-connect"
        },
      })

      -- 200
      local oidc_route = bp.routes:insert({
        service = oidc_service,
        hosts = { "success.oidc.konghq.com" },
      })

      db.konnect_applications:insert({
        client_id = client_id,
        scopes = { uuid(), scope, uuid() }
      })

      -- ctx-checker will simulate OIDC plugin running before Konnect Application Auth
      -- to add authenticated_credential to the ctx
      bp.plugins:insert({
        name = "ctx-checker",
        route = { id = oidc_route.id },
        config = {
          ctx_set_field = "authenticated_credential",
          ctx_set_map = { id = client_id },
        }
      })

      -- 401 no ctx added for this route, will be unauthed
      bp.routes:insert({
        service = oidc_service,
        hosts = { "unauthed.oidc.konghq.com" },
      })

      -- 403 client id does not map to an application
      local forbidden_oidc_route_1 = bp.routes:insert({
        service = oidc_service,
        hosts = { "forbidden.oidc.konghq.com" },
      })

      bp.plugins:insert({
        name = "ctx-checker",
        route = { id = forbidden_oidc_route_1.id },
        config = {
          ctx_set_field = "authenticated_credential",
          ctx_set_map = { id = forbidden_client_id_1 },
        }
      })

      -- 403 application has nil scopes
      local forbidden_oidc_route_2 = bp.routes:insert({
        service = oidc_service,
        hosts = { "forbidden2.oidc.konghq.com" },
      })

      db.konnect_applications:insert({
        client_id = forbidden_client_id_2
      })

      bp.plugins:insert({
        name = "ctx-checker",
        route = { id = forbidden_oidc_route_2.id },
        config = {
          ctx_set_field = "authenticated_credential",
          ctx_set_map = { id = forbidden_client_id_2 },
        }
      })

      -- 403 application has empty scopes
      local forbidden_oidc_route_3 = bp.routes:insert({
        service = oidc_service,
        hosts = { "forbidden3.oidc.konghq.com" },
      })

      db.konnect_applications:insert({
        client_id = forbidden_client_id_3,
        scopes = {}
      })

      bp.plugins:insert({
        name = "ctx-checker",
        route = { id = forbidden_oidc_route_3.id },
        config = {
          ctx_set_field = "authenticated_credential",
          ctx_set_map = { id = forbidden_client_id_3 },
        }
      })

      -- 403 application scopes does not contain plugins tracking id
      local forbidden_oidc_route_4 = bp.routes:insert({
        service = oidc_service,
        hosts = { "forbidden4.oidc.konghq.com" },
      })

      db.konnect_applications:insert({
        client_id = forbidden_client_id_4,
        scopes = { uuid(), uuid(), uuid() }
      })

      bp.plugins:insert({
        name = "ctx-checker",
        route = { id = forbidden_oidc_route_4.id },
        config = {
          ctx_set_field = "authenticated_credential",
          ctx_set_map = { id = forbidden_client_id_4 },
        }
      })

      -- Key auth
      local key_auth_service = bp.services:insert({
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      })

      bp.routes:insert({
        service = key_auth_service,
        hosts = { "keyauth.konghq.com" },
      })

      bp.plugins:insert({
        name = PLUGIN_NAME,
        service = key_auth_service,
        config = {
          scope = scope,
          auth_type = "key-auth"
        },
      })

      db.konnect_applications:insert({
        client_id = hash_key("opensesame"),
        scopes = { scope }
      })

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME .. ",ctx-checker",
        -- write & load declarative config, only if 'strategy=off'
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("OIDC", function()
      it("returns 401 if no client ID found in authenticated credential", function ()
        local res = client:get("/request", {
          headers = {
            host = "unauthed.oidc.konghq.com"
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "Unauthorized")
      end)

      it("returns 403 if client ID does not map to an application", function()
        local res = client:get("/request", {
          headers = {
            host = "forbidden.oidc.konghq.com"
          }
        })

        local body = assert.res_status(403, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "You cannot consume this service")
      end)

      it("returns 403 if client ID's application has no tracking ids (nil)", function()
        local res = client:get("/request", {
          headers = {
            host = "forbidden2.oidc.konghq.com"
          }
        })

        local body = assert.res_status(403, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "You cannot consume this service")
      end)

      it("returns 403 if client ID's application has no tracking ids (empty table)", function()
        local res = client:get("/request", {
          headers = {
            host = "forbidden3.oidc.konghq.com"
          }
        })

        local body = assert.res_status(403, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "You cannot consume this service")
      end)

      it("returns 403 if client ID's application does not contain the correct tracking id", function()
        local res = client:get("/request", {
          headers = {
            host = "forbidden4.oidc.konghq.com"
          }
        })

        local body = assert.res_status(403, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "You cannot consume this service")
      end)

      it("returns 200 if client ID's application contain the correct tracking id", function()
        local res = client:get("/request", {
          headers = {
            host = "success.oidc.konghq.com"
          }
        })

        assert.res_status(200, res)
      end)
    end)

    describe("Key-auth", function ()
      it("returns 401 if api key found", function ()
        local res = client:get("/request", {
          headers = {
            host = "keyauth.konghq.com"
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "Unauthorized")
      end)

      it("returns 401 if api key in query is invalid", function ()
        local res = client:get("/request?apikey=derp", {
          headers = {
            host = "keyauth.konghq.com"
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "Unauthorized")
      end)

      it("returns 401 if api key in header is invalid", function ()
        local res = client:get("/request", {
          headers = {
            apikey = "derp",
            host = "keyauth.konghq.com"
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "Unauthorized")
      end)

      it("returns 200 if api key found in query", function ()
        local res = client:get("/request?apikey=opensesame", {
          headers = {
            host = "keyauth.konghq.com"
          }
        })

       assert.res_status(200, res)
      end)

      it("returns 200 if api key found in headers", function ()
        local res = client:get("/request", {
          headers = {
            apikey = "opensesame",
            host = "keyauth.konghq.com"
          }
        })

       assert.res_status(200, res)
      end)
    end)
  end)
end
