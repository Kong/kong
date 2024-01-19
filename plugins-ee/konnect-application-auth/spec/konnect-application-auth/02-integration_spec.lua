-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson.safe"
local sha256_hex = require "kong.tools.sha256".sha256_hex


local helpers = require "spec.helpers"
local uuid = require("kong.tools.utils").uuid


local PLUGIN_NAME = "konnect-application-auth"



for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client
    local client_id = uuid()
    local forbidden_client_id_1 = uuid()
    local forbidden_client_id_2 = uuid()
    local forbidden_client_id_3 = uuid()
    local forbidden_client_id_4 = uuid()
    local key_auth_service_consumer_group
    local consumer_group1
    local consumer_group2

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
        hosts = { "success.oidc.konghq.test" },
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
        hosts = { "unauthed.oidc.konghq.test" },
      })

      -- 403 client id does not map to an application
      local forbidden_oidc_route_1 = bp.routes:insert({
        service = oidc_service,
        hosts = { "forbidden.oidc.konghq.test" },
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
        hosts = { "forbidden2.oidc.konghq.test" },
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
        hosts = { "forbidden3.oidc.konghq.test" },
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
        hosts = { "forbidden4.oidc.konghq.test" },
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
        hosts = { "keyauth.konghq.test" },
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
        client_id = sha256_hex("opensesame"),
        scopes = { scope }
      })

      -- Consumer group
      key_auth_service_consumer_group = bp.services:insert({
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      })

      bp.routes:insert({
        service = key_auth_service_consumer_group,
        hosts = { "keyauthconsumergroup.konghq.test" },
      })

      bp.plugins:insert({
        name = PLUGIN_NAME,
        service = key_auth_service_consumer_group,
        config = {
          scope = scope,
          auth_type = "key-auth"
        },
      })

      bp.plugins:insert {
        name = "post-function",
          service = key_auth_service_consumer_group,
          config = {
            header_filter = {[[
              local c = kong.client.get_consumer_groups()
              if c then
                local names = {}
                for i, v in ipairs(c) do
                  table.insert(names, v.name)
                end
                kong.response.set_header("x-consumer-groups-kaa", table.concat(names,","))
              end
              kong.response.set_header("x-test", "kaa")

              local app_ctx = kong.ctx.shared.kaa_application_context
              kong.response.set_header("x-app-id", app_ctx and app_ctx.application_id or "nil")
              kong.response.set_header("x-dev-id", app_ctx and app_ctx.developer_id or "nil")
              kong.response.set_header("x-org-id", app_ctx and app_ctx.organization_id or "nil")
              kong.response.set_header("x-portal-id", app_ctx and app_ctx.portal_id or "nil")
              kong.response.set_header("x-product-version-id", app_ctx and app_ctx.product_version_id or "nil")
            ]]}
          }
      }

      db.konnect_applications:insert({
        client_id = sha256_hex("opendadoor"),
        scopes = { scope },
        consumer_groups = {"imindaband1","imindaband2"},
        application_context = {
          application_id = "app_id",
          organization_id = "org_id",
          developer_id = "dev_id",
          portal_id = "portal_id",
        }
      })

      db.konnect_applications:insert({
        client_id = sha256_hex("opendadoor2"),
        scopes = { scope },
        consumer_groups = {"idontexist"}
      })

      db.konnect_applications:insert({
        client_id = sha256_hex("exhausted"),
        scopes = { scope },
        exhausted_scopes = { scope },
      })

      db.konnect_applications:insert({
        client_id = sha256_hex("not_exhausted"),
        scopes = { scope },
        exhausted_scopes = { "something_else" },
      })

      consumer_group1 = db.consumer_groups:insert({
        name = "imindaband1"
      })

      consumer_group2 = db.consumer_groups:insert({
        name = "imindaband2"
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
            host = "unauthed.oidc.konghq.test"
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "Unauthorized")
      end)

      it("returns 403 if client ID does not map to an application", function()
        local res = client:get("/request", {
          headers = {
            host = "forbidden.oidc.konghq.test"
          }
        })

        local body = assert.res_status(403, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "You cannot consume this service")
      end)

      it("returns 403 if client ID's application has no tracking ids (nil)", function()
        local res = client:get("/request", {
          headers = {
            host = "forbidden2.oidc.konghq.test"
          }
        })

        local body = assert.res_status(403, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "You cannot consume this service")
      end)

      it("returns 403 if client ID's application has no tracking ids (empty table)", function()
        local res = client:get("/request", {
          headers = {
            host = "forbidden3.oidc.konghq.test"
          }
        })

        local body = assert.res_status(403, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "You cannot consume this service")
      end)

      it("returns 403 if client ID's application does not contain the correct tracking id", function()
        local res = client:get("/request", {
          headers = {
            host = "forbidden4.oidc.konghq.test"
          }
        })

        local body = assert.res_status(403, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "You cannot consume this service")
      end)

      it("returns 200 if client ID's application contain the correct tracking id", function()
        local res = client:get("/request", {
          headers = {
            host = "success.oidc.konghq.test"
          }
        })

        assert.res_status(200, res)
      end)
    end)

    describe("Key-auth", function ()
      it("returns 401 if api key found", function ()
        local res = client:get("/request", {
          headers = {
            host = "keyauth.konghq.test"
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "Unauthorized")
      end)

      it("returns 401 if api key in query is invalid", function ()
        local res = client:get("/request?apikey=derp", {
          headers = {
            host = "keyauth.konghq.test"
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
            host = "keyauth.konghq.test"
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "Unauthorized")
      end)

      it("returns 200 if api key found in query", function ()
        local res = client:get("/request?apikey=opensesame", {
          headers = {
            host = "keyauth.konghq.test"
          }
        })

       assert.res_status(200, res)
      end)

      it("returns 200 if api key found in headers", function ()
        local res = client:get("/request", {
          headers = {
            apikey = "opensesame",
            host = "keyauth.konghq.test"
          }
        })

       assert.res_status(200, res)
      end)
    end)

    describe("Key-auth consumer groups", function()

      it("maps the consumer groups if found", function()
        local res = client:get("/request?apikey=opendadoor", {
            headers = {
                host = "keyauthconsumergroup.konghq.test"
            }
        })

        assert.res_status(200, res)
        assert.are.same(consumer_group1.name .. "," .. consumer_group2.name, res.headers["x-consumer-groups-kaa"])
        assert.are.same("kaa", res.headers["x-test"])
      end)

      it("doesnt map the consumer groups if not found", function()
        local res = client:get("/request?apikey=opendadoor2", {
            headers = {
                host = "keyauthconsumergroup.konghq.test"
            }
        })

        assert.res_status(200, res)
        assert.are.same(nil, res.headers["x-consumer-groups-kaa"])
        assert.are.same("kaa", res.headers["x-test"])
      end)

      it("doesnt map the consumer groups if request fails", function()
        local res = client:get("/request", {
            headers = {
                host = "keyauthconsumergroup.konghq.test"
            }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)

        assert.equal(json.message, "Unauthorized")
        assert.are.same(nil, res.headers["x-consumer-groups-kaa"])
        assert.are.same("kaa", res.headers["x-test"])
      end)

    end)

    describe("Key-auth application context", function()
      it("maps the application context when found", function()
        local res = client:get("/request?apikey=opendadoor", {
            headers = {
                host = "keyauthconsumergroup.konghq.test"
            }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.are.same("kaa", res.headers["x-test"])

        -- post Function mapped headers
        assert.are.same("app_id", res.headers["x-app-id"])
        assert.are.same("dev_id", res.headers["x-dev-id"])
        assert.are.same("org_id", res.headers["x-org-id"])
        assert.are.same("portal_id", res.headers["x-portal-id"])
        assert.are.same(scope, res.headers["x-product-version-id"])

        -- proxyied headers
        assert.are.same("app_id", json.headers["x-application-id"])
        assert.are.same("dev_id", json.headers["x-application-developer-id"])
        assert.are.same("org_id", json.headers["x-application-org-id"])
        assert.are.same("portal_id", json.headers["x-application-portal-id"])
      end)
      it("doesnt map the application context when not found", function()
        local res = client:get("/request?apikey=opendadoor2", {
            headers = {
                host = "keyauthconsumergroup.konghq.test"
            }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.are.same("kaa", res.headers["x-test"])

        -- post Function mapped headers
        assert.are.same("nil", res.headers["x-app-id"])
        assert.are.same("nil", res.headers["x-dev-id"])
        assert.are.same("nil", res.headers["x-org-id"])
        assert.are.same("nil", res.headers["x-portal-id"])
        assert.are.same("nil", res.headers["x-product-version-id"])

        -- proxyied headers
        assert.are.same(nil, json.headers["x-application-id"])
        assert.are.same(nil, json.headers["x-application-developer-id"])
        assert.are.same(nil, json.headers["x-application-org-id"])
        assert.are.same(nil, json.headers["x-application-portal-id"])
      end)
    end)
    describe("exhausted applications", function()
      it("rate limit the metered application", function()
        local res = client:get("/request", {
          headers = {
            apikey = "exhausted",
            host = "keyauth.konghq.test"
          }
        })

        assert.res_status(429, res)
      end)

      it("doesnt rate limit the application when exhausted on another service", function()
        local res = client:get("/request", {
          headers = {
            apikey = "not_exhausted",
            host = "keyauth.konghq.test"
          }
        })

        assert.res_status(200, res)
      end)
    end)
  end)
end
