local pl_file    = require "pl.file"
local pl_path    = require "pl.path"
local helpers      = require "spec.helpers"
local ee_helpers   = require "spec-ee.helpers"
local singletons   = require "kong.singletons"

local function create_portal_index()
  local prefix = singletons.configuration and singletons.configuration.prefix or 'servroot/'
  local portal_dir = 'portal'
  local portal_path = prefix .. portal_dir
  local views_path = portal_path .. '/views'
  local index_filename = views_path .. "/index.etlua"
  local index_str = "<% for key, value in pairs(configs) do %>  <meta name=\"KONG:<%= key %>\" content=\"<%= value %>\" /><% end %>"

  if not pl_path.exists(portal_path) then
    pl_path.mkdir(portal_path)
  end

  if not pl_path.exists(views_path) then
    pl_path.mkdir(views_path)
  end
  
  pl_file.write(index_filename, index_str)
end


-- TODO: Cassandra
for _, strategy in helpers.each_strategy({'postgres'}) do
  describe("#flaky portal index", function()
    local dao
    local client

    setup(function()
      _, _, dao = helpers.get_db_utils(strategy)
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    describe("router", function ()
      local portal_gui_client

      describe("portal_gui_use_subdomains = off", function()
        before_each(function()
          helpers.stop_kong()
          helpers.register_consumer_relations(dao)
  
          assert(helpers.start_kong({
            database    = strategy,
            portal      = true,
            portal_auth = "basic-auth",
            portal_gui_use_subdomains = false,
          }))
  
          client = assert(helpers.admin_client())
          portal_gui_client = assert(ee_helpers.portal_gui_client())
          create_portal_index()
        end)
  
        after_each(function()
          if client then
            client:close()
          end
  
          if portal_gui_client then
            portal_gui_client:close()
          end
        end)

        it("correctly identifies default workspace", function()
          local res = assert(portal_gui_client:send {
            method = "GET",
            path = "/",
          })
          local body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="default" />'))
  
          res = assert(portal_gui_client:send {
            method = "GET",
            path = "/hello",
          })
          body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="default" />'))
  
          res = assert(portal_gui_client:send {
            method = "GET",
            path = "/hello/goodbye",
          })
          body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="default" />'))
        end)
  
        it("correctly identifies custom workspace", function()  
          assert(client:send {
            method = "POST",
            path = "/workspaces",
            body = {
              name = "team_gruce",
            },
            headers = {["Content-Type"] = "application/json"},
          })
  
          local res = assert(portal_gui_client:send {
            method = "GET",
            path = "/"
          })
          local body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="default" />'))
  
          res = assert(portal_gui_client:send {
            method = "GET",
            path = "/team_gruce"
          })
          body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
  
          res = assert(portal_gui_client:send {
            method = "GET",
            path = "/team_gruce/endpoint"
          })
          body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
  
          res = assert(portal_gui_client:send {
            method = "GET",
            path = "/team_gruce/endpoint/another_endpoint"
          })
          body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
  
          res = assert(portal_gui_client:send {
            method = "GET",
            path = "/team_gruce/default"
          })
          body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
        end)
  
        it("correctly overrides default (conf.default) config when workspace config present", function()  
          assert(client:send {
            method = "POST",
            path = "/workspaces",
            body = {
              name = "team_gruce",
              config = {
                portal_auth = "key-auth"
              },
            },
            headers = {["Content-Type"] = "application/json"},
          })
  
          local res = assert(portal_gui_client:send {
            method = "GET",
            path = "/default"
          })
          local body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:PORTAL_AUTH" content="basic%-auth" />'))
  
          res = assert(portal_gui_client:send {
            method = "GET",
            path = "/team_gruce"
          })
          body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:PORTAL_AUTH" content="key%-auth" />'))
        end)
      end)

      describe("portal_gui_use_subdomains = on", function()
        local portal_gui_host
        local portal_gui_protocol

        before_each(function()
          helpers.stop_kong()
          helpers.register_consumer_relations(dao)

          portal_gui_host = 'cat.hotdog.com'
          portal_gui_protocol = 'http'
  
          assert(helpers.start_kong({
            database    = strategy,
            portal      = true,
            portal_auth = "basic-auth",
            portal_gui_host = portal_gui_host,
            portal_gui_protocol = portal_gui_protocol,
            portal_gui_use_subdomains = true,
          }))
  
          client = assert(helpers.admin_client())
          portal_gui_client = assert(ee_helpers.portal_gui_client())
          create_portal_index()
        end)
  
        after_each(function()
          if client then
            client:close()
          end
  
          if portal_gui_client then
            portal_gui_client:close()
          end
        end)

        it("correctly identifies default workspace", function()
          local res = assert(portal_gui_client:send {
            method = "GET",
            path = "/",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://default.' .. portal_gui_host,
              ['Host'] = 'default.' .. portal_gui_host,
            },
          })
          local body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="default" />'))
  
          res = assert(portal_gui_client:send {
            method = "GET",
            path = "/hello",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://default.' .. portal_gui_host,
              ['Host'] = 'default.' .. portal_gui_host,
            },
          })
          body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="default" />'))
        end)
  
        it("correctly identifies custom workspace", function()  
          assert(client:send {
            method = "POST",
            path = "/workspaces",
            body = {
              name = "team_gruce",
            },
            headers = {["Content-Type"] = "application/json"},
          })
  
          local res = assert(portal_gui_client:send {
            method = "GET",
            path = "/",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://team_gruce.' .. portal_gui_host,
              ['Host'] = 'team_gruce.' .. portal_gui_host,
            },
          })
          local body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
  
          res = assert(portal_gui_client:send {
            method = "GET",
            path = "/hotdog",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://team_gruce.' .. portal_gui_host,
              ['Host'] = 'team_gruce.' .. portal_gui_host,
            },
          })
          body = assert.res_status(200, res)
          assert.not_nil(string.match(body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
        end)

        it("returns 500 if subdomain not included", function()  
          assert(client:send {
            method = "POST",
            path = "/workspaces",
            body = {
              name = "team_gruce",
            },
            headers = {["Content-Type"] = "application/json"},
          })
  
          local res = assert(portal_gui_client:send {
            method = "GET",
            path = "/",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://' .. portal_gui_host,
              ['Host'] = portal_gui_host,
            },
          })
          local body = assert.res_status(500, res)
          assert.not_nil(string.match(body, '{"message":"An unexpected error occurred"}'))
        end)

        it("returns 500 if subdomain is not a recognized workspace", function()  
          assert(client:send {
            method = "POST",
            path = "/workspaces",
            body = {
              name = "team_gruce",
            },
            headers = {["Content-Type"] = "application/json"},
          })
  
          local res = assert(portal_gui_client:send {
            method = "GET",
            path = "/",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://wrong_workspace.' .. portal_gui_host,
              ['Host'] = 'wrong_workspace.' .. portal_gui_host,
            },
          })
          local body = assert.res_status(500, res)
          assert.not_nil(string.match(body, '{"message":"An unexpected error occurred"}'))
        end)

        it("returns 500 if subdomain is invalid", function()  
          assert(client:send {
            method = "POST",
            path = "/workspaces",
            body = {
              name = "team_gruce",
            },
            headers = {["Content-Type"] = "application/json"},
          })
  
          local res = assert(portal_gui_client:send {
            method = "GET",
            path = "/",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://wrong_workspace,' .. portal_gui_host,
              ['Host'] = 'wrong_workspace,' .. portal_gui_host,
            },
          })
          local body = assert.res_status(500, res)
          assert.not_nil(string.match(body, '{"message":"An unexpected error occurred"}'))
        end)
      end)
    end)
  end)
end
