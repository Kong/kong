-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ee_helpers = require "spec-ee.helpers"
local helpers    = require "spec.helpers"

local clear_license_env = require("spec-ee.02-integration.04-dev-portal.utils").clear_license_env
local parse_url = require("socket.url").parse

local escape_uri = ngx.escape_uri

local PORTAL_SESSION_CONF = "{ \"secret\": \"super-secret\", \"cookie_secure\": false }"

local function configure_portal(db, workspace_name)
  local workspace = db.workspaces:select_by_name(workspace_name)

  db.workspaces:update({
    id = workspace.id
  },
  {
    config = {
      portal = true,
    }
  })
end


local function close_clients(clients)
  for idx, client in ipairs(clients) do
    client:close()
  end
end


local function client_request(params)
  local client = assert(helpers.admin_client())
  local res = assert(client:send(params))
  res.body = res:read_body()

  close_clients({ client })

  return res
end


local function gui_client_request(params)
  local portal_gui_client = assert(ee_helpers.portal_gui_client())
  local res = assert(portal_gui_client:send(params))
  res.body = res:read_body()

  close_clients({ portal_gui_client })
  return res
end


local function create_workspace_files(workspace_name)
  -- portal conf
  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      path = "portal.conf.yaml",
      contents = [[
        name: Kong Portal
        theme:
          name: test-theme
      ]],
    },
    headers = {["Content-Type"] = "application/json"},
  })

  -- theme conf
  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      path = "themes/test-theme/theme.conf.yaml",
      contents = [[
        name: Kong
        fonts:
          base: Roboto
          code: Roboto Mono
          headings: Lato
        colors:
          header:
            value: '#FFFFFF'
            description: Background for header
          page:
            value: '#FFFFFF'
            description: Background on pages
          hero:
            value: '#003459'
            description: 'Background for hero text on hompage, about, login, contact us...'
      ]]
    },
    headers = {["Content-Type"] = "application/json"},
  })

  -- layout-base
  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      path = "themes/test-theme/layouts/base.html",
      contents = [[
        <!DOCTYPE html>
        <html>
          <head>
            <title>{{portal.name}} - {{ page.title }} </title>
            <link href="assets/styles/site.css" rel="stylesheet" />
          </head>
          <body>
            <div class="page">
             {* blocks.content *}
            </div>
            <p>workspace is {{portal.workspace}}</p>
          </body>
        </html>
      ]]
    },
    headers = {["Content-Type"] = "application/json"},
  })

  -- layout-home
  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      path = "themes/test-theme/layouts/home.html",
      contents = [[
        {% layout = "layouts/base.html" %}

        {-content-}
        <div>
          <div class="hero">
            <h1>{{page.hero.title}}</h1>
          </div>
          <p>{{page.body}}</p>
        <div>
        {-content-}
      ]]
    },
    headers = {["Content-Type"] = "application/json"},
  })

  -- layout-about
  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      path = "themes/test-theme/layouts/about.html",
      contents = [[
        {% layout = "layouts/base.html" %}

        {-content-}
        <div>
          <p>{{page.stringy}}</p>
        <div>
        {-content-}
      ]]
    },
    headers = {["Content-Type"] = "application/json"},
  })

  -- layout-404
  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      path = "themes/test-theme/layouts/system/404.html",
      contents = [[
        {% layout = "layouts/base.html" %}

        {-content-}
        <div>
          <h1>You found this super cute 404 🐈</h1>
        <div>
        {-content-}
      ]]
    },
    headers = {["Content-Type"] = "application/json"},
  })

   -- content-index
  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      path = "content/index.txt",
      contents = [[
        ---
        layout: home.html

        title: test home-y

        hero:
          title: Making Data Available. Sometimes. Someplaces

        body: wow much website
        ---
      ]]
    },
    headers = {["Content-Type"] = "application/json"},
  })

  -- content-about
  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      path = "content/about.txt",
      contents = [[
        ---
        layout: about.html

        title: About Us

        stringy: we are about passing tests
        ---
      ]]
    },
    headers = {["Content-Type"] = "application/json"},
  })

end



local reset_license_data

for _, strategy in helpers.each_strategy() do

  describe("router #" .. strategy, function ()

    setup(function()
      reset_license_data = clear_license_env()
    end)

    teardown(function()
      reset_license_data()
    end)

    describe("portal_gui_use_subdomains = off", function()
      local db

      setup(function()
        _, db, _ = helpers.get_db_utils(strategy)
        assert(helpers.start_kong({
          database    = strategy,
          portal      = true,
          portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
          license_path = "spec-ee/fixtures/mock_license.json",
          portal_gui_use_subdomains = false,
          portal_is_legacy = false,
          portal_auth = "basic-auth",
          portal_auto_approve = true,
          portal_session_conf = PORTAL_SESSION_CONF,
        }))

        configure_portal(db, "default")


        local res = client_request({
          method = "POST",
          path = "/workspaces",
          body = {
            name = "team_gruce",
            config = {
              portal_auth = "key-auth",
              portal = true
            },
          },
          headers = {["Content-Type"] = "application/json"},
        })
        assert.equals(201, res.status)

        ngx.sleep(5)
        db:truncate("files")

        create_workspace_files("default")
        create_workspace_files("team_gruce")
        ngx.sleep(2)
      end)

      teardown(function()
        db:truncate()
        helpers.stop_kong()
      end)

      it("correctly identifies default workspace", function()
        local res = gui_client_request({
          method = "GET",
          path = "/",
        })
        assert.equals(res.status, 302)
        assert.equals(parse_url(res.headers.Location).path, '/default')


        local res = gui_client_request({
          method = "GET",
          path = "/default",
        })
        assert.equals(res.status, 200)
        assert.not_nil(string.match(res.body, 'wow much website'))
        assert.not_nil(string.match(res.body, 'workspace is default'))

        local res = gui_client_request({
          method = "GET",
          path = "/about",
        })
        assert.equals(res.status, 200)

        assert.not_nil(string.match(res.body, 'we are about passing tests'))
        assert.not_nil(string.match(res.body, 'workspace is default'))

        local res = gui_client_request({
          method = "GET",
          path = "/default/about",
        })
        assert.equals(res.status, 200)

        assert.not_nil(string.match(res.body, 'we are about passing tests'))
        assert.not_nil(string.match(res.body, 'workspace is default'))

        local res = gui_client_request({
          method = "GET",
          path = "/badroute",
        })
        assert.equals(res.status, 200)

        assert.not_nil(string.match(res.body, 'super cute 404 🐈'))
        assert.not_nil(string.match(res.body, 'workspace is default'))


        local res = gui_client_request({
          method = "GET",
          path = "/default/badroute",
        })
        assert.equals(res.status, 200)

        assert.not_nil(string.match(res.body, 'super cute 404 🐈'))
        assert.not_nil(string.match(res.body, 'workspace is default'))

      end)

      it("404s on non-conformant custom workspace", function()
        local res = gui_client_request({
          method = "GET",
          path = "/&&&",
        })
        assert.equals(res.status, 404)

      end)

      it("correctly identifies custom workspace", function()
        local res = gui_client_request({
          method = "GET",
          path = "/team_gruce",
        })
        assert.equals(res.status, 200)
        assert.not_nil(string.match(res.body, 'wow much website'))
        assert.not_nil(string.match(res.body, 'workspace is team_gruce'))


        local res = gui_client_request({
          method = "GET",
          path = "/team_gruce/about",
        })
        assert.equals(res.status, 200)

        assert.not_nil(string.match(res.body, 'we are about passing tests'))
        assert.not_nil(string.match(res.body, 'workspace is team_gruce'))

        local res = gui_client_request({
          method = "GET",
          path = "/team_gruce/badroute",
        })
        assert.equals(res.status, 200)

        assert.not_nil(string.match(res.body, 'super cute 404 🐈'))
        assert.not_nil(string.match(res.body, 'workspace is team_gruce'))

      end)
    end)

    describe("portal_gui_use_subdomains = on", function()
      local db
      local portal_gui_host, portal_gui_protocol

      setup(function()
        _, db, _ = helpers.get_db_utils(strategy)
        portal_gui_host = 'cat.hotdog.com'
        portal_gui_protocol = 'http'

        assert(helpers.start_kong({
          database    = strategy,
          portal      = true,
          portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
          license_path = "spec-ee/fixtures/mock_license.json",
          portal_auth = "basic-auth",
          portal_auto_approve = true,
          portal_is_legacy = false,
          portal_gui_use_subdomains = true,
          portal_session_conf = PORTAL_SESSION_CONF,
          portal_gui_host = portal_gui_host,
          portal_gui_protocol = portal_gui_protocol,
        }))

        configure_portal(db, "default")

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

        ngx.sleep(5)
        db:truncate('files')

        create_workspace_files("default")
        create_workspace_files("team_gruce")
        ngx.sleep(2)
      end)

      teardown(function()
        db:truncate()
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

        assert.not_nil(string.match(res.body, 'wow much website'))
        assert.not_nil(string.match(res.body, 'workspace is default'))

        res = gui_client_request({
          method = "GET",
          path = "/about",
          headers = {
            ['Origin'] = portal_gui_protocol .. '://default.' .. portal_gui_host,
            ['Host'] = 'default.' .. portal_gui_host,
          },
        })
        assert.equals(200, res.status)

        assert.not_nil(string.match(res.body, 'we are about passing tests'))
        assert.not_nil(string.match(res.body, 'workspace is default'))

        res = gui_client_request({
          method = "GET",
          path = "/badroute",
          headers = {
            ['Origin'] = portal_gui_protocol .. '://default.' .. portal_gui_host,
            ['Host'] = 'default.' .. portal_gui_host,
          },
        })
        assert.equals(200, res.status)

        assert.not_nil(string.match(res.body, 'super cute 404 🐈'))
        assert.not_nil(string.match(res.body, 'workspace is default'))

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

        assert.not_nil(string.match(res.body, 'wow much website'))
        assert.not_nil(string.match(res.body, 'workspace is team_gruce'))

        res = gui_client_request({
          method = "GET",
          path = "/about",
          headers = {
            ['Origin'] = portal_gui_protocol .. '://team_gruce.' .. portal_gui_host,
            ['Host'] = 'team_gruce.' .. portal_gui_host,
          },
        })
        assert.equals(200, res.status)

        assert.not_nil(string.match(res.body, 'we are about passing tests'))
        assert.not_nil(string.match(res.body, 'workspace is team_gruce'))

        res = gui_client_request({
          method = "GET",
          path = "/badroute",
          headers = {
            ['Origin'] = portal_gui_protocol .. '://team_gruce.' .. portal_gui_host,
            ['Host'] = 'team_gruce.' .. portal_gui_host,
          },
        })
        assert.equals(200, res.status)

        assert.not_nil(string.match(res.body, 'super cute 404 🐈'))
        assert.not_nil(string.match(res.body, 'workspace is team_gruce'))

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

      it("returns 404 if subdomain doesn't match existing portal", function()
        local res = gui_client_request({
          method = "GET",
          path = "/",
          headers = {
            ['Origin'] = portal_gui_protocol .. '://wrong_workspace,' .. portal_gui_host,
            ['Host'] = 'wrong_workspace,' .. portal_gui_host,
          },
        })
        assert.equals(404, res.status)
      end)
    end)

    describe("router refresh", function()
      local db

      setup(function()
        _, db, _ = helpers.get_db_utils(strategy)
        assert(helpers.start_kong({
          database    = strategy,
          portal      = true,
          portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
          license_path = "spec-ee/fixtures/mock_license.json",
          portal_is_legacy = false,
        }))

        configure_portal(db, "default")

        ngx.sleep(5)
        db:truncate("files")

        create_workspace_files("default")
        ngx.sleep(2)
      end)

      teardown(function()
        db:truncate()
        helpers.stop_kong()
      end)

      it("regression - refreshes after consecutive CRUD actions on single file", function()
        assert(client_request({
          method = "POST",
          path = "/default/files",
          body = {
            path = "content/specs.txt",
            contents =  [[
              ---
              layout: specs.html
              ---
            ]]
          },
          headers = {["Content-Type"] = "application/json"},
        }))

        assert(client_request({
          method = "POST",
          path = "/default/files",
          body = {
            path = "themes/test-theme/layouts/specs.html",
            contents =  [[
              {% for _, spec in each(portal.specs_by_tag()) do %}
                <h1>{{spec.parsed.info.title}}</h1>
              {% end %}
            ]]
          },
          headers = {["Content-Type"] = "application/json"},
        }))

        assert(client_request({
          method = "POST",
          path = "/default/files",
          body = {
            path = "specs/dog.yaml",
            contents = [[
              openapi: 3.0.0
              info:
                title: DogsRKewl
                version: 1.0.0
            ]]
          },
          headers = {["Content-Type"] = "application/json"},
        }))

        gui_client_request({
          method = "GET",
          path = "/default/specs",
        })

        local res = gui_client_request({
          method = "GET",
          path = "/default/specs",
        })
        assert.equals(res.status, 200)

        assert.not_nil(string.match(res.body, 'DogsRKewl'))

        assert(client_request({
          method = "DELETE",
          path = "/default/files/specs/dog.yaml",
          headers = {["Content-Type"] = "application/json"},
        }))

        -- force router rebuild
        gui_client_request({
          method = "GET",
          path = "/default/specs",
        })

        ngx.sleep(2)

        res = gui_client_request({
          method = "GET",
          path = "/default/specs",
        })
        assert.equals(res.status, 200)

        assert.is_nil(string.match(res.body, 'DogsRKewl'))
      end)
    end)

    describe("default route", function()
      local db

      setup(function()
        _, db, _ = helpers.get_db_utils(strategy)
        assert(helpers.start_kong({
          database    = strategy,
          portal      = true,
          portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
          license_path = "spec-ee/fixtures/mock_license.json",
          portal_is_legacy = false,
        }))

        configure_portal(db, "default")

        ngx.sleep(5)
        db:truncate("files")

        create_workspace_files("default")
        ngx.sleep(2)
      end)

      teardown(function()
        db:truncate()
        helpers.stop_kong()
      end)

      it("returns 404 when passed an illegal redirect in path", function()
        local res = assert(gui_client_request({
          method = "GET",
          path = "//wwww.google.com/",
        }))

        assert.res_status(404, res)
      end)
    end)

    describe("workspace that contains special chars", function()
      local db

      setup(function()
        _, db, _ = helpers.get_db_utils(strategy)
        assert(helpers.start_kong({
          database    = strategy,
          portal      = true,
          portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
          license_path = "spec-ee/fixtures/mock_license.json",
          portal_gui_use_subdomains = false,
          portal_is_legacy = false,
          portal_auth = "basic-auth",
          portal_auto_approve = true,
          portal_session_conf = PORTAL_SESSION_CONF
        }))

        local res = client_request({
          method = "POST",
          path = "/workspaces",
          body = {
            name = "ws-Áæ",
            config = {
              portal_auth = "key-auth",
              portal = true
            },
          },
          headers = {["Content-Type"] = "application/json"},
        })
        assert.equals(201, res.status)
      end)

      teardown(function()
        db:truncate()
        helpers.stop_kong()
      end)

      it("correctly unescape the url to identify routes", function()
        local ws_name_escaped = escape_uri("ws-Áæ")
        local res = gui_client_request({
          method = "GET",
          path = "/" .. ws_name_escaped,
        })
        assert.equals(res.status, 200)

        local res = gui_client_request({
          method = "GET",
          path = "/" .. ws_name_escaped .. "/documentation",
        })
        assert.equals(res.status, 200)
      end)
    end)
  end)
end
