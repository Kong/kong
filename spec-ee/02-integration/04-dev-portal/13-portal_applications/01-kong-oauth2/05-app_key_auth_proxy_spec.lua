-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local cjson      = require "cjson"
local helpers    = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key


for _, strategy in helpers.each_strategy() do
  describe("Developer Portal - Application Key-Auth Proxy access #" .. strategy, function()
    local portal_api_client
    local proxy_client
    local cookie
    local application
    local reset_license_data

    local bp, db, _ = helpers.get_db_utils(strategy)

    lazy_setup(function()
      reset_license_data = clear_license_env()
      helpers.stop_kong()
      assert(db:truncate())

      local service = assert(bp.services:insert())

      assert(bp.routes:insert {
        service = { id = service.id },
        paths = { "/" },
        methods = { "GET", "POST" },
        protocols = { "http", "https" },
      })

      assert(db.plugins:insert({
        name = "application-registration",
        service = { id = service.id },
        config = {
          display_name = "my service",
          auto_approve = true
        },
      }))

      bp.plugins:insert({
        name     = "key-auth",
        service = { id = service.id }
      })

      assert(helpers.start_kong({
        database   = strategy,
        license_path = "spec-ee/fixtures/mock_license.json",
        portal_session_conf = "{ \"secret\": \"super-secret\", \"cookie_secure\": false }",
        portal = true,
        portal_and_vitals_key = get_portal_and_vitals_key(),
        portal_auth = "basic-auth",
        portal_app_auth = "kong-oauth2",
        portal_auto_approve = true,
        admin_gui_url = "http://localhost:8080",
        portal_auth_login_attempts = 3,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      assert(db.workspaces:upsert_by_name("default", {
        name = "default",
        config = {
          portal = true,
          portal_auth = "basic-auth",
          portal_auto_approve = true,
        },
      }))

      portal_api_client = assert(ee_helpers.portal_api_client())

      local res = portal_api_client:send({
        method = "POST",
        path = "/register",
        body = {
          email = "gruce@konghq.com",
          password = "kong",
          meta = "{\"full_name\":\"I Like Turtles\"}",
        },
        headers = {["Content-Type"] = "application/json"},
      })

      assert.res_status(200, res)

      local res = assert(portal_api_client:send {
        method = "GET",
        path = "/auth",
        headers = {
          ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
        }
      })

      assert.res_status(200, res)

      cookie = assert.response(res).has.header("Set-Cookie")

      local res = assert(portal_api_client:send {
        method = "POST",
        path = "/applications",
        body = {
          name = "myfirstapp",
          redirect_uri = "http://dog.test"
        },
        headers = {
          ["Content-Type"] = "application/json",
          ["Cookie"] = cookie
        }
      })

      local body = assert.res_status(200, res)
      application = cjson.decode(body)

      local res = assert(portal_api_client:send {
        method = "POST",
        path = "/applications/" .. application.id .. "/application_instances",
        body = {
          service = {
            id = service.id
          }
        },
        headers = {
          ["Cookie"] = cookie,
          ["Content-Type"] = "application/json",
        }
      })

      assert.res_status(201, res)

      portal_api_client:close()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      assert(db:truncate())
      reset_license_data()
    end)

    before_each(function()
      portal_api_client = assert(ee_helpers.portal_api_client())
      proxy_client = assert(helpers.proxy_client())
    end)

    after_each(function()
      if portal_api_client then
        portal_api_client:close()
      end

      if proxy_client then
        proxy_client:close()
      end
    end)

    it("cannot access the service without a key", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
      })
      assert.res_status(401, res)
    end)

    it("can use client_id from application credential as a key", function()
      local res = assert(portal_api_client:send {
        method = "GET",
        path = "/applications/" .. application.id .. "/credentials",
        headers = {
          ["Cookie"] = cookie,
          ["Content-Type"] = "application/json",
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local key = json.data[1].client_id

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200?apikey=" .. key,
      })
      assert.res_status(200, res)
    end)
  end)
end
