local pl_file    = require "pl.file"
local pl_path    = require "pl.path"
local helpers      = require "spec.helpers"
local ee_helpers   = require "spec-ee.helpers"
local singletons   = require "kong.singletons"

local PORTAL_SESSION_CONF = "{ \"cookie_name\": \"portal_session\", \"secret\": \"super-secret\", \"cookie_secure\": false, \"storage\": \"kong\" }"

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


local function close_clients(clients)
  for idx, client in ipairs(clients) do
    client:close()
  end
end


local function client_request(params)
  local client = assert(helpers.admin_client())
  local res = assert(client:send(params))
  res.body = res.body_reader()

  close_clients({ client })
  return res
end


local function gui_client_request(params)
  local portal_gui_client = assert(ee_helpers.portal_gui_client())
  local res = assert(portal_gui_client:send(params))
  res.body = res.body_reader()

  close_clients({ portal_gui_client })
  return res
end


local function create_workspace_files(workspace_name)

  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      name = "unauthenticated/index",
      auth = false,
      type = "page",
      contents = [[
        <h1>index page</h1>
      ]],
    },
    headers = {["Content-Type"] = "application/json"},
  })

  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      name = "unauthenticated/login",
      auth = false,
      type = "page",
      contents = [[
        <h1>login page<h2>
      ]]
    },
    headers = {["Content-Type"] = "application/json"},
  })

  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      name = "unauthenticated/404",
      auth = false,
      type = "page",
      contents = [[
        <h1>404 page<h2>
      ]]
    },
    headers = {["Content-Type"] = "application/json"},
  })
end


-- TODO: Cassandra
for _, strategy in helpers.each_strategy('postgres') do
  describe("portal index", function()
    local dao

    setup(function()
      _, _, dao = helpers.get_db_utils(strategy)
    end)

    describe("router", function ()
      describe("portal_gui_use_subdomains = off", function()

        setup(function()
          helpers.register_consumer_relations(dao)
          assert(helpers.start_kong({
            database    = strategy, 
            portal      = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
            portal_session_conf = PORTAL_SESSION_CONF,
          }))
          create_portal_index()

          local res = client_request({
            method = "POST",
            path = "/workspaces",
            body = {
              name = "team_gruce",
              config = {
                portal_auth = "key-auth",
                portal = true,
              },
            },
            headers = {["Content-Type"] = "application/json"},
          })
          assert.equals(201, res.status)

          create_workspace_files("default")
        end)

        teardown(function()
          dao:truncate_table('files')
          helpers.stop_kong()
        end)

        it("correctly identifies default workspace", function()
          local res = gui_client_request({
            method = "GET",
            path = "/",
          })
          assert.equals(res.status, 200)
          assert.not_nil(string.match(res.body, '<meta name="KONG:WORKSPACE" content="default" />'))
          
          res = gui_client_request({
            method = "GET",
            path = "/test",
          })
          assert.equals(res.status, 200)
          assert.not_nil(string.match(res.body, '<meta name="KONG:WORKSPACE" content="default" />'))
          
          res = gui_client_request({
            method = "GET",
            path = "/nested/test",
          })
          assert.equals(res.status, 200)
          assert.not_nil(string.match(res.body, '<meta name="KONG:WORKSPACE" content="default" />'))
        end)
  
        it("correctly identifies custom workspace", function()
          local res = gui_client_request({
            method = "GET",
            path = "/"
          })
          assert.equals(res.status, 200)
          assert.not_nil(string.match(res.body, '<meta name="KONG:WORKSPACE" content="default" />'))
  
          res = gui_client_request({
            method = "GET",
            path = "/team_gruce"
          })
          assert.equals(res.status, 200)
          assert.not_nil(string.match(res.body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
  
          res = gui_client_request({
            method = "GET",
            path = "/team_gruce/endpoint"
          })
          assert.equals(res.status, 200)
          assert.not_nil(string.match(res.body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
  
          res = gui_client_request({
            method = "GET",
            path = "/team_gruce/endpoint/another_endpoint"
          })
          assert.equals(res.status, 200)
          assert.not_nil(string.match(res.body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
  
          res = gui_client_request({
            method = "GET",
            path = "/team_gruce/default"
          })
          assert.equals(res.status, 200)
          assert.not_nil(string.match(res.body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
        end)
  
        it("correctly overrides default (conf.default) config when workspace config present", function()  
          local res = gui_client_request({
            method = "GET",
            path = "/default"
          })
          assert.equals(res.status, 200)
          assert.not_nil(string.match(res.body, '<meta name="KONG:PORTAL_AUTH" content="basic%-auth" />'))
  
          res = gui_client_request({
            method = "GET",
            path = "/team_gruce"
          })
          assert.equals(res.status, 200)
          assert.not_nil(string.match(res.body, '<meta name="KONG:PORTAL_AUTH" content="key%-auth" />'))
        end)
      end)

      describe("portal_gui_use_subdomains = on", function()
        local portal_gui_host, portal_gui_protocol

        setup(function()
          helpers.register_consumer_relations(dao)

          portal_gui_host = 'cat.hotdog.com'
          portal_gui_protocol = 'http'
      
          assert(helpers.start_kong({
            database    = strategy, 
            portal      = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
            portal_gui_use_subdomains = true,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal_gui_host = portal_gui_host,
            portal_gui_protocol = portal_gui_protocol,
          }))
          create_portal_index()

          local res = client_request({
            method = "POST",
            path = "/workspaces",
            body = {
              name = "team_gruce",
              config = {
                portal_auth = "key-auth",
                portal = true,
              },
            },
            headers = {["Content-Type"] = "application/json"},
          })
          assert.equals(201, res.status)

          create_workspace_files("default")
        end)

        teardown(function()
          dao:truncate_table('files')
          helpers.stop_kong()
        end)

        it("correctly identifies default workspace", function()
          local res = gui_client_request({
            method = "GET",
            path = "/",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://default.' .. portal_gui_host,
              ['Host'] = 'default.' .. portal_gui_host,
            },
          })
          assert.equals(200, res.status)
          assert.not_nil(string.match(res.body, '<meta name="KONG:WORKSPACE" content="default" />'))
  
          res = gui_client_request({
            method = "GET",
            path = "/hello",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://default.' .. portal_gui_host,
              ['Host'] = 'default.' .. portal_gui_host,
            },
          })
          assert.equals(200, res.status)
          assert.not_nil(string.match(res.body, '<meta name="KONG:WORKSPACE" content="default" />'))
        end)
  
        it("correctly identifies custom workspace", function()  
          local res = gui_client_request({
            method = "GET",
            path = "/",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://team_gruce.' .. portal_gui_host,
              ['Host'] = 'team_gruce.' .. portal_gui_host,
            },
          })
          assert.equals(200, res.status)
          assert.not_nil(string.match(res.body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
  
          res = gui_client_request({
            method = "GET",
            path = "/hotdog",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://team_gruce.' .. portal_gui_host,
              ['Host'] = 'team_gruce.' .. portal_gui_host,
            },
          })
          assert.equals(200, res.status)
          assert.not_nil(string.match(res.body, '<meta name="KONG:WORKSPACE" content="team_gruce" />'))
        end)

        it("returns 500 if subdomain not included", function()  
          local res = gui_client_request({
            method = "GET",
            path = "/",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://' .. portal_gui_host,
              ['Host'] = portal_gui_host,
            },
          })
          assert.equals(500, res.status)
          assert.not_nil(string.match(res.body, '{"message":"An unexpected error occurred"}'))
        end)

        it("returns 500 if subdomain is not a recognized workspace", function()  
          local res = gui_client_request({
            method = "GET",
            path = "/",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://wrong_workspace.' .. portal_gui_host,
              ['Host'] = 'wrong_workspace.' .. portal_gui_host,
            },
          })
          assert.equals(500, res.status)
          assert.not_nil(string.match(res.body, '{"message":"An unexpected error occurred"}'))
        end)

        it("returns 500 if subdomain is invalid", function()  
          local res = gui_client_request({
            method = "GET",
            path = "/",
            headers = {
              ['Origin'] = portal_gui_protocol .. '://wrong_workspace,' .. portal_gui_host,
              ['Host'] = 'wrong_workspace,' .. portal_gui_host,
            },
          })
          assert.equals(500, res.status)
          assert.not_nil(string.match(res.body, '{"message":"An unexpected error occurred"}'))
        end)
      end)
    end)
  end)
end
