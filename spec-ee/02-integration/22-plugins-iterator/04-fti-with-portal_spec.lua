-- this software is copyright kong inc. and its licensors.
-- use of the software is subject to the agreement between your organization
-- and kong inc. if there is no such agreement, use is governed by and
-- subject to the terms of the kong master software license agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ end of license 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local conf_loader = require "kong.conf_loader"
local cjson = require("cjson")

local function configure_portal(db, workspace_name, config)
  assert(db.workspaces:upsert_by_name(workspace_name, {
    name = workspace_name,
    config = config,
  }))
end

for _, strategy in helpers.all_strategies({ "postgres" }) do
  describe("FTI-4945 return intermittent 401 strategy-" .. strategy, function()
    local bp, db, service, portal_api_client, proxy_client

    lazy_setup(function()
      helpers.kill_all()

      assert(conf_loader(nil, {
        plugins = { "application-registration", "pre-function", "correlation-id", "key-auth",
          "basic_auth" }
      }))

      bp, db = helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
        "services",
      }, { "application-registration" })

      service = bp.services:insert {
        protocol = "http",
        host     = "localhost",
        path     = "/",
        port     = 9001
      }
      bp.routes:insert {
        paths   = { "/test" },
        service = { id = service.id }
      }

      -- add services scope plugins key-auth, application-registration
      bp.plugins:insert({
        name    = "key-auth",
        service = { id = service.id }
      })

      bp.plugins:insert({
        name    = "application-registration",
        config  = {
          display_name = "dev portal",
          auto_approve = true,
        },
        service = { id = service.id },
      })

      -- add global scope plugins correlation-id, pre-function
      bp.plugins:insert({
        name = "correlation-id",
      })

      bp.plugins:insert({
        name = "pre-function",
        config = {
          access = { [[kong.log("access")]] }
        },
        ordering = {
          after = {
            access = { "correlation-id" }
          }
        }
      })

      assert(helpers.start_kong {
        plugins             = "bundled,application-registration",
        database            = strategy,
        nginx_conf          = "spec/fixtures/custom_nginx.template",
        portal              = true,
        portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
        portal_cors_origins = "*",
        portal_gui_protocol = "http",
        portal_auth         = "basic-auth",
        portal_session_conf = "{ \"secret\": \"super-secret\", \"cookie_secure\": false }",
      })

      configure_portal(db, "default", {
        portal              = true,
        portal_auth         = "basic-auth",
        portal_is_legacy    = true,
        portal_auto_approve = true,
      })

      portal_api_client = assert(ee_helpers.portal_api_client())
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      proxy_client:close()
      -- helpers.stop_kong()
    end)

    after_each(function()
      db:truncate("routes")
      db:truncate("services")
      db:truncate("plugins")
      db:truncate("developers")
      db:truncate("applications")
    end)

    it("ordering with dev portal", function()
      --register developer
      local res = portal_api_client:send({
        method = "POST",
        path = "/register",
        body = {
          email = "gruce@konghq.com",
          password = "kong",
          meta = "{\"full_name\":\"I Like Turtles\"}",
        },
        headers = { ["Content-Type"] = "application/json" },
      })

      assert.res_status(200, res)

      -- developers login dev portal
      local res = assert(portal_api_client:send {
        method = "GET",
        path = "/auth",
        headers = {
          ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
        }
      })

      assert.res_status(200, res)

      local cookie = assert.response(res).has.header("Set-Cookie")

      -- create a new application
      local res = assert(portal_api_client:send {
        method = "POST",
        path = "/applications",
        body = {
          name = "myfirstapp",
          redirect_uri = "http://dog.com"
        },
        headers = {
          ["Content-Type"] = "application/json",
          ["Cookie"] = cookie
        }
      })

      local body = assert.res_status(200, res)
      local application = cjson.decode(body)

      local res = assert(portal_api_client:send({
        method = "POST",
        path = "/applications/" .. application.id .. "/application_instances",
        body = {
          service = { id = service.id },
        },
        headers = {
          ["Content-Type"] = "application/json",
          ["Cookie"] = cookie
        }
      }))

      assert.res_status(201, res)

      --reterieve client id from application
      local res = assert(portal_api_client:send({
        method = "GET",
        path = "/applications/" .. application.id .. "/credentials",
        headers = {
          ["Cookie"] = cookie
        }
      }))

      local body = assert.res_status(200, res)
      local credential = cjson.decode(body).data[1]

      -- create 100 requests
      local count = 100
      for _ = 1, count do
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/test",
          headers = {
            ["apiKey"] = credential.client_id
          }
        })
        assert.response(res).has.status(200)
      end

      portal_api_client:close()
    end)
  end)
end
