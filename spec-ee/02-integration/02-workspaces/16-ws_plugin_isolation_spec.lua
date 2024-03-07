-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local cjson = require("cjson")
local helpers = require("spec.helpers")
local workspaces = require("kong.workspaces")

for _, strategy in helpers.each_strategy() do
  describe(
   "workspace plugin config isolation #" .. strategy,
   function()
     local bp
     local db
     local admin_client
     local proxy_client
     local default_ws_plugin
     local sandbox_plugin
     local sandbox_service

     lazy_setup(function()
       bp, db = helpers.get_db_utils(strategy, {
         "routes",
         "services",
         "plugins",
         "consumers",
         "keyauth_credentials",
       })

       db:truncate("services")
       db:truncate("routes")
       db:truncate("plugins")
       db:truncate("consumers")
       db:truncate("keyauth_credentials")

       -- we set a config in the default workspace that is different
       -- then then the config used by any other named workspace
       default_ws_plugin = assert(
        bp.plugins:insert_ws({
          name = "key-auth",
          config = {key_names = {"notinuse"}},
        }, workspaces.DEFAULT_WORKSPACE))
       assert.True(default_ws_plugin.enabled)

       local sandbox_ws = assert(
        bp.workspaces:insert{name = "sandbox"})

       sandbox_service = bp.services:insert_ws(
        {
          name = "mock_upstream",
          protocol = "http",
          path = "/anything",
          host = helpers.mock_upstream_host,
          port = helpers.mock_upstream_port,
        }, sandbox_ws)

       bp.routes:insert_ws({
         protocols = {"http", "https"},
         hosts = {"mock_upstream"},
         methods = {"GET"},
         service = sandbox_service,
       }, sandbox_ws)

       -- this is _different_ than the default workspace's
       -- key-auth plugin config
       sandbox_plugin = assert(
        bp.plugins:insert_ws({
          name = "key-auth",
          config = {key_names = {"sandboxkey"}},
          service = {id = sandbox_service.id},
        }, sandbox_ws))
       assert.True(sandbox_plugin.enabled)

       local consumer1 = bp.consumers:insert_ws(
        {username = "consumer1"}, sandbox_ws)

       bp.keyauth_credentials:insert_ws(
        {key = "apikey123", consumer = {id = consumer1.id}},
        sandbox_ws)

       -- start Kong instance with our services and plugins
       assert(helpers.start_kong {
         database = strategy,
         -- /!\ test with real nginx config
       })

       --  start mock httpbin instance
       assert(helpers.start_kong {
         database = strategy,
         admin_listen = "127.0.0.1:9011",
         proxy_listen = "127.0.0.1:9010",
         proxy_listen_ssl = "127.0.0.1:9453",
         admin_listen_ssl = "127.0.0.1:9454",
         prefix = "servroot2",
         nginx_conf = "spec/fixtures/custom_nginx.template",
       })
     end)

     lazy_teardown(function()
       helpers.stop_kong("servroot2")
       helpers.stop_kong()
     end)

     before_each(function()
       if admin_client and proxy_client then
         admin_client:close()
         proxy_client:close()
       end

       admin_client = assert(helpers.admin_client())
       proxy_client = assert(helpers.proxy_client())
     end)

     -- following each test we ensure the plugins are enabled
     -- in both the default and sandbox workspace
     after_each(function()
       local res = assert(admin_client:send{
         method = "PATCH",
         path = "/plugins/" .. default_ws_plugin.id,
         body = {enabled = true},
         headers = {["Content-Type"] = "application/json"},
       })
       assert.res_status(200, res)

       res = assert(admin_client:send{
         method = "PATCH",
         path = "/sandbox/services/" .. sandbox_service.name ..
          "/plugins/" .. sandbox_plugin.id,
         body = {enabled = true},
         headers = {["Content-Type"] = "application/json"},
       })
       assert.res_status(200, res)
     end)

     describe(
      "when enabled in the default and named workspace",
      function()
        describe("GET named workspace service", function()
          it(
           "works with the locally scoped plugin header config",
           function()
             local res = assert(
              proxy_client:send{
                method = "GET",
                path = "/status/200",
                headers = {
                  ["Host"] = "mock_upstream",
                  -- using the plugin config from the sandbox workspace
                  ["sandboxkey"] = "apikey123",
                },
              })
             local body = assert.res_status(200, res)
             local json = cjson.decode(body)
             assert.same("mock_upstream",
                         json.vars.server_name)
           end)
        end)
      end)

     describe(
      "when enabled in the default but disabled in the named workspace",
      function()
        lazy_setup(function()
          local res = assert(admin_client:send{
            method = "PATCH",
            path = "/sandbox/services/" ..
             sandbox_service.name .. "/plugins/" ..
             sandbox_plugin.id,
            body = {enabled = false},
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          assert.res_status(200, res)
        end)

        describe("GET named workspace service", function()
          it("works without requiring any plugin headers",
             function()
               helpers.wait_until(function()
                 return pcall(function()
                   local res = assert(
                    proxy_client:send{
                      method = "GET",
                      path = "/status/200",
                     -- no key-auth header required since the default
                     -- workspace does not have this service route
                      headers = {["Host"] = "mock_upstream"},
                    })
                   local body = assert.res_status(200, res)
                   local json = cjson.decode(body)
                   assert.same("mock_upstream",
                               json.vars.server_name)
                 end)
              end)
          end)
        end)
      end)

     describe(
      "when disabled in the default and enabled in the named workspace",
      function()
        lazy_setup(function()
          local res = assert(admin_client:send{
            method = "PATCH",
            path = "/plugins/" .. default_ws_plugin.id,
            body = {enabled = false},
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          assert.res_status(200, res)
        end)

        describe("GET named workspace service", function()
          it(
           "works with the locally scoped plugin header config",
           function()
             local res = assert(
              proxy_client:send{
                method = "GET",
                path = "/status/200",
                headers = {
                  ["Host"] = "mock_upstream",
                  -- using the plugin config from the sandbox workspace
                  ["sandboxkey"] = "apikey123",
                },
              })
             local body = assert.res_status(200, res)
             local json = cjson.decode(body)
             assert.same("mock_upstream",
                         json.vars.server_name)

           end)
        end)
      end)
   end)
end
