-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: application-registration (EE) (access) [#" .. strategy .. "]", function()
    local proxy_client,
          proxy_ssl_client,
          admin_client,
          consumer,
          service,
          bp,
          db

    before_each(function()
      bp, db = helpers.get_db_utils(strategy, {
        "acls",
        "services",
        "plugins",
        "routes",
        "consumers",
        "oauth2_credentials",
      })

      service = assert(bp.services:insert())

      assert(bp.routes:insert {
        service = { id = service.id },
        paths = { "/httpbin" },
        methods = { "GET", "POST" },
        protocols = { "http", "https" },
      })

      assert(bp.oauth2_plugins:insert({
        service = { id = service.id },
        config = {
          enable_client_credentials = true,
          scopes = { "bork" },
        },
      }))

      assert(db.plugins:insert({
        name = "application-registration",
        service = { id = service.id },
        config = {
          display_name = "my service",
        },
      }))

      consumer = assert(bp.consumers:insert {
        username = "fake_application",
        custom_id = "1234",
        type = 3,
      })

      assert(bp.oauth2_credentials:insert({
        consumer  = { id = consumer.id },
        name = "testapplication",
        client_id = "doggo",
        client_secret = "cat",
        redirect_uris = { "http://some-domain/endpoint/" }
      }))

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
      proxy_ssl_client = helpers.proxy_ssl_client()
    end)

    after_each(function()
      db:truncate("acls")
      db:truncate("plugins")
      db:truncate("routes")
      db:truncate("services")
      db:truncate("consumers")
      db:truncate("oauth2_credentials")

      if proxy_client then
        proxy_client:close()
      end
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    it("returns 403 when valid group not given", function()
      local res = assert(proxy_ssl_client:send {
        method  = "POST",
        path    = "/httpbin/oauth2/token",
        body    = {
          client_id        = "doggo",
          client_secret    = "cat",
          grant_type       = "client_credentials",
          scope            = "bork",
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      local token = assert.response(res).has.jsonbody()
      assert.is_table(token)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/httpbin/status/200",
        headers = {
          ["authorization"] = "bearer " .. token.access_token
        }
      })

      assert.res_status(403, res)
    end)

    it("returns 200 when passed valid access token", function()
      assert(bp.acls:insert {
        group    = service.id,
        consumer = { id = consumer.id },
      })

      local res = assert(proxy_ssl_client:send {
        method  = "POST",
        path    = "/httpbin/oauth2/token",
        body    = {
          client_id        = "doggo",
          client_secret    = "cat",
          grant_type       = "client_credentials",
          scope            = "bork",
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      local token = assert.response(res).has.jsonbody()
      assert.is_table(token)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/httpbin/status/200",
        headers = {
          ["authorization"] = "bearer " .. token.access_token
        }
      })

      assert.res_status(200, res)
    end)
  end)
end
