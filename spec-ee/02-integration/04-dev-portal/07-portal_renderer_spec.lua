local cjson   = require "cjson"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local stringx = require "pl.stringx"
local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local singletons = require "kong.singletons"

local PORTAL_SESSION_CONF = "{ \"cookie_name\": \"portal_session\", \"secret\": \"super-secret\", \"cookie_secure\": false, \"storage\": \"kong\" }"


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


local function api_client_request(params)
  local portal_api_client = assert(ee_helpers.portal_api_client())
  local res = assert(portal_api_client:send(params))
  res.body = res.body_reader()

  close_clients({ portal_api_client })
  return res
end


local function gui_client_request(params)
  local portal_gui_client = assert(ee_helpers.portal_gui_client())
  local res = assert(portal_gui_client:send(params))
  res.body = res.body_reader()

  close_clients({ portal_gui_client })
  return res
end


local function register_developer(params)
  return api_client_request({
    method = "POST",
    path = "/register",
    body = params,
    headers = {["Content-Type"] = "application/json"},
  })
end


local function configure_portal(db)
  db.workspaces:upsert_by_name("default", {
    name = "default",
    config = {
      portal = true,
    },
  })
end


local function create_portal_index()
  local prefix = singletons.configuration and singletons.configuration.prefix or 'servroot/'
  local portal_dir = 'portal'
  local portal_path = prefix .. portal_dir
  local views_path = portal_path .. '/views'
  local index_filename = views_path .. "/index.etlua"
  local index_str =
    [[
      <div id="page" style="display: none">
        <%= page %>
      </div>
      <div id="spec" style="display: none">
        <%= spec %>
      </div>
      <div id="partials" style="display: none">
        <%= partials %>
      </div>
    ]]

  if not pl_path.exists(portal_path) then
    pl_path.mkdir(portal_path)
  end

  if not pl_path.exists(views_path) then
    pl_path.mkdir(views_path)
  end

  pl_file.write(index_filename, index_str)
end

local function create_portal_sitemap()
  local prefix = singletons.configuration and singletons.configuration.prefix or 'servroot/'
  local portal_dir = 'portal'
  local portal_path = prefix .. portal_dir
  local views_path = portal_path .. '/views'
  local sitemap_filename = views_path .. "/sitemap.etlua"
  local sitemap_str =
    [[
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <% for idx, url_obj in pairs(xml_urlset) do %>
          <url>
            <% for key, value in pairs(url_obj) do %>
              <<%=key%>><%=value%></<%=key%>>
            <% end %>
          </url>
        <% end %>
      </urlset>
    ]]

  if not pl_path.exists(portal_path) then
    pl_path.mkdir(portal_path)
  end

  if not pl_path.exists(views_path) then
    pl_path.mkdir(views_path)
  end

  pl_file.write(sitemap_filename, sitemap_str)
end


for _, strategy in helpers.each_strategy() do


  -- TODO DEVX: re-impliment once api endpoints are done
  if strategy == 'cassandra' then
    return
  end

  pending("Portal Rendering [#" .. strategy .. "]", function()
    local db
    local cookie

    lazy_setup(function()
      _, db, _ = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database    = strategy,
        portal      = true,
        enforce_rbac = "off",
        portal_auth = "key-auth",
        portal_auto_approve = true,
        portal_session_conf = PORTAL_SESSION_CONF,
      }))
      configure_portal(db)
      create_portal_index()
      create_portal_sitemap()
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    describe("pages", function()
      local auth_page_pair, unauth_page_pair, auth_page_solo,
            unauth_page_solo, login_page, not_found_page,
            namespaced_index_page, namespaced_page

      lazy_setup(function()
        assert(register_developer({
          email = "catdog@konghq.com",
          key = "dog",
          meta = "{\"full_name\":\"catdog\"}",
        }))

        local res = api_client_request({method = "GET",
          path = "/auth",
          headers = {
            ['apikey'] = 'dog'
          }
        })
        cookie = assert.response(res).has.header("Set-Cookie")

        auth_page_pair = assert(db.files:insert {
          name = "page_pair",
          auth = true,
          type = "page",
          contents = [[
            <h1>auth_page_pair<h2>
          ]]
        })

        unauth_page_pair = assert(db.files:insert {
          name = "unauthenticated/page_pair",
          auth = false,
          type = "page",
          contents = [[
            <h1>unauth_page_pair<h2>
          ]]
        })

        auth_page_solo = assert(db.files:insert {
          name = "auth_page_solo",
          auth = true,
          type = "page",
          contents = [[
            <h1>auth_page_solo<h2>
          ]]
        })

        unauth_page_solo = assert(db.files:insert {
          name = "unauthenticated/unauth_page_solo",
          auth = false,
          type = "page",
          contents = [[
            <h1>unauth_page_solo<h2>
          ]]
        })

        login_page = assert(db.files:insert {
          name = "unauthenticated/login",
          auth = false,
          type = "page",
          contents = [[
            <h1>login<h2>
          ]]
        })

        not_found_page = assert(db.files:insert {
          name = "unauthenticated/404",
          auth = false,
          type = "page",
          contents = [[
            <h1>404<h2>
          ]]
        })

        namespaced_index_page = assert(db.files:insert {
          name = "documentation/index",
          auth = true,
          type = "page",
          contents = [[
            <h1>index<h2>
          ]]
        })

        namespaced_page = assert(db.files:insert {
          name = "documentation/page",
          auth = true,
          type = "page",
          contents = [[
            <h1>page<h2>
          ]]
        })
      end)

      lazy_teardown(function()
        db:truncate("files")
        -- db:truncate('consumers')
      end)

      describe("unauthenticated user", function()
        it("can render unauthenticated page with auth pair", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/page_pair",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, unauth_page_pair.id))
        end)

        it("can render unauthenticated page with auth pair by explicitly calling it", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/unauthenticated/page_pair",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, unauth_page_pair.id))
        end)

        it("can render unauthenticated page with no auth page pair", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/unauth_page_solo",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, unauth_page_solo.id))
        end)

        it("can render login page when authenticated page is called for", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/auth_page_solo",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, login_page.id))
        end)
      end)

      describe("authenticated user", function()
        it("can render authenticated page with unauthenticated pair", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/page_pair",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, auth_page_pair.id))
        end)

        it("can render unauthenticated page with auth pair by explicit name", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/unauthenticated/page_pair",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, unauth_page_pair.id))
        end)

        it("can render unauthenticated page with no auth page pair", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/unauth_page_solo",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, unauth_page_solo.id))
        end)

        it("can render authenticated page with no unauth page pair", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/auth_page_solo",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, auth_page_solo.id))
        end)

        it("can render 404 when no page found", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/blahblahblah",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, not_found_page.id))
        end)
      end)

      describe("special cases", function()
        it("can render index page when namespace is called", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/documentation",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, namespaced_index_page.id))
        end)

        it("can render namespaced page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/documentation/page",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, namespaced_page.id))
        end)

        it("can render 404 page when page not found", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/asdfasdfasdf",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, not_found_page.id))
        end)

        it("can render login page when unauthenticated", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/auth_page_solo",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, login_page.id))
        end)

        describe("OIDC authentication", function()
          local oidc_auth_page_pair, oidc_unauth_page_pair

          lazy_setup(function()
            local res = client_request({
              method = "POST",
              path = "/workspaces",
              body = {
                name = "oidc-test",
                config = {
                  portal = true,
                  portal_auth = "openid-connect",
                  portal_auth_conf = {
                    issuer = "https://accounts.google.com/"
                  }
                }
              },
              headers = {["Content-Type"] = "application/json"},
            })

            assert.equals(201, res.status)

            res = client_request({
              method = "POST",
              path = "/oidc-test/files",
              body = {
                name = "page_pair",
                auth = true,
                type = "page",
                contents = [[
                  <h1>auth_page_pair<h2>
                ]],
              },
              headers = {["Content-Type"] = "application/json"},
            })
            oidc_auth_page_pair = cjson.decode(res.body)

            res = client_request({
              method = "POST",
              path = "/oidc-test/files",
              body = {
                name = "unauthenticated/page_pair",
                auth = false,
                type = "page",
                contents = [[
                  <h1>unauth_page_pair<h2>
                ]]
              },
              headers = {["Content-Type"] = "application/json"},
            })
            oidc_unauth_page_pair = cjson.decode(res.body)
          end)

          lazy_teardown(function()
            client_request({
              method = "DELETE",
              path = "/workspaces/oidc-test",
            })
          end)

          it("renders unauthenticated page when no session cookie set", function()
            local res = gui_client_request({
              method = "GET",
              path = "/oidc-test/page_pair",
            })

            local status = res.status
            local body = res.body

            assert.equals(200, status)
            assert.equals(0, stringx.count(body, oidc_auth_page_pair.id))
            assert.equals(1, stringx.count(body, oidc_unauth_page_pair.id))
          end)
        end)

        describe("No authentication", function()
          local noauth_not_found, noauth_login, noauth_register,
                noauth_dashboard, noauth_settings

          lazy_setup(function()
            local res = client_request({
              method = "POST",
              path = "/workspaces",
              body = {
                name = "noauth-test",
                config = {
                  portal = true,
                  portal_auth = "",
                }
              },
              headers = {["Content-Type"] = "application/json"},
            })
            assert.equals(res.status, 201)

            res = client_request({
              method = "GET",
              path = "/noauth-test/files/unauthenticated/404"
            })
            noauth_not_found = cjson.decode(res.body)

            res = client_request({
              method = "GET",
              path = "/noauth-test/files/unauthenticated/login",
            })
            noauth_login = cjson.decode(res.body)

            res = client_request({
              method = "GET",
              path = "/noauth-test/files/unauthenticated/register",
            })
            noauth_register = cjson.decode(res.body)

            res = client_request({
              method = "GET",
              path = "/noauth-test/files/dashboard",
            })
            noauth_dashboard = cjson.decode(res.body)

            res = client_request({
              method = "GET",
              path = "/noauth-test/files/settings",
            })
            noauth_settings = cjson.decode(res.body)
          end)

          lazy_teardown(function()
            client_request({
              method = "DELETE",
              path = "/workspaces/noauth-test",
            })
          end)

          it("renders 404 page when blacklisted pages are requested", function()
            local res = gui_client_request({
              method = "GET",
              path = "/noauth-test/dashboard",
            })
            local status = res.status
            local body = res.body

            assert.equals(200, status)
            assert.equals(0, stringx.count(body, noauth_dashboard.id))
            assert.equals(1, stringx.count(body, noauth_not_found.id))

            res = gui_client_request({
              method = "GET",
              path = "/noauth-test/login",
            })
            status = res.status
            body = res.body

            assert.equals(200, status)
            assert.equals(0, stringx.count(body, noauth_login.id))
            assert.equals(1, stringx.count(body, noauth_not_found.id))

            res = gui_client_request({
              method = "GET",
              path = "/noauth-test/register",
            })
            status = res.status
            body = res.body

            assert.equals(200, status)
            assert.equals(0, stringx.count(body, noauth_register.id))
            assert.equals(1, stringx.count(body, noauth_not_found.id))

            res = gui_client_request({
              method = "GET",
              path = "/noauth-test/settings",
            })
            status = res.status
            body = res.body

            assert.equals(200, status)
            assert.equals(0, stringx.count(body, noauth_settings.id))
            assert.equals(1, stringx.count(body, noauth_not_found.id))
          end)
        end)
      end)
    end)

    describe("partials", function()
      local auth_partial, auth_page_pair, unauth_page_pair,
            unauth_partial, nested_partial_parent, nested_partial_child,
            infinite_loop_page, infinite_loop_partial, formatting_page,
            block_syntax_partial, strange_spacing_partial, partial_with_argument,
            improper_format_partial

      lazy_setup(function()
        assert(register_developer({
          email = "catdog@konghq.com",
          key = "dog",
          meta = "{\"full_name\":\"catdog\"}",
        }))

        local res = api_client_request({method = "GET",
          path = "/auth",
          headers = {
            ['apikey'] = 'dog'
          }
        })
        cookie = assert.response(res).has.header("Set-Cookie")

        auth_page_pair = assert(db.files:insert {
          name = "page_pair",
          auth = true,
          type = "page",
          contents = [[
            <h1>auth_page_pair<h2>
            {{> partial }}
            {{> unauthenticated/partial }}
            {{> nested_partial_parent }}
          ]]
        })

        unauth_page_pair = assert(db.files:insert {
          name = "unauthenticated/page_pair",
          auth = false,
          type = "page",
          contents = [[
            <h1>unauth_page_pair<h2>
            {{> partial }}
            {{> unauthenticated/partial }}
            {{> nested_partial_parent }}
          ]]
        })

        auth_partial = assert(db.files:insert {
          name = "partial",
          auth = true,
          type = "partial",
          contents = [[
            <h1>auth_partial<h1>
          ]]
        })

        unauth_partial = assert(db.files:insert {
          name = "unauthenticated/partial",
          auth = false,
          type = "partial",
          contents = [[
            <h1>unauth_partial<h1>
          ]]
        })

        nested_partial_parent = assert(db.files:insert {
          name = "nested_partial_parent",
          auth = true,
          type = "partial",
          contents = [[
            <h1>nested_partial_parent<h1>
            {{> nested_partial_child }}
          ]]
        })

        nested_partial_child = assert(db.files:insert {
          name = "nested_partial_child",
          auth = true,
          type = "partial",
          contents = [[
            <h1>nested_partial_child<h1>
          ]]
        })

        infinite_loop_page = assert(db.files:insert {
          name = "infinite_loop_page",
          auth = true,
          type = "page",
          contents = [[
            <h1>partial_page_loop<h1>
            {{> infinite_loop_partial }}
          ]]
        })

        infinite_loop_partial = assert(db.files:insert {
          name = "infinite_loop_partial",
          auth = true,
          type = "partial",
          contents = [[
            <h1>infinite_loop_partial<h1>
            {{> infinite_loop_partial }}
          ]]
        })

        formatting_page = assert(db.files:insert {
          name = "formatting_page",
          auth = true,
          type = "page",
          contents = [[
            <h1>formatting_page<h1>
            {{#> block_syntax_partial }}
              {{> partial }}
            {{/ block_syntax_partial }}
            {{>     strange_spacing_partial}}
            {{> partial_with_argument dog=cat }}
            {> improper_format_partial }}
            {{ improper_format_partial }}
            {{ improper_format_partial }}
            { improper_format_partial }
          ]]
        })

        block_syntax_partial = assert(db.files:insert {
          name = "block_syntax_partial",
          auth = true,
          type = "partial",
          contents = [[
            <h1>block_syntax_partial<h1>
          ]]
        })

        strange_spacing_partial = assert(db.files:insert {
          name = "strange_spacing_partial",
          auth = true,
          type = "partial",
          contents = [[
            <h1>strange_spacing_partial<h1>
          ]]
        })

        partial_with_argument = assert(db.files:insert {
          name = "partial_with_argument",
          auth = true,
          type = "partial",
          contents = [[
            <h1>partial_with_argument<h1>
          ]]
        })

        improper_format_partial = assert(db.files:insert {
          name = "improper_format_partial",
          auth = true,
          type = "partial",
          contents = [[
            <h1>improper_format_partial<h1>
          ]]
        })
      end)

      lazy_teardown(function()
        db:truncate("files")
        -- db:truncate('consumers')
      end)

      describe("authenticated user", function()
        it("can render authenticated partials", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/page_pair",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(status, 200)
          assert.equals(1, stringx.count(body, auth_page_pair.id))
          assert.equals(1, stringx.count(body, auth_partial.id))
        end)

        it("can render unauthenticated partials", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/page_pair",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(status, 200)
          assert.equals(1, stringx.count(body, auth_page_pair.id))
          assert.equals(1, stringx.count(body, unauth_partial.id))
        end)
      end)

      describe("unauthenticated user", function()
        it("can render unauthenticated partials", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/page_pair",
          })
          local status = res.status
          local body = res.body

          assert.equals(status, 200)
          assert.equals(1, stringx.count(body, unauth_page_pair.id))
          assert.equals(1, stringx.count(body, unauth_partial.id))
        end)

        it("cannot render authenticated partials", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/page_pair",
          })
          local status = res.status
          local body = res.body

          assert.equals(status, 200)
          assert.equals(1, stringx.count(body, unauth_page_pair.id))
          assert.equals(0, stringx.count(body, auth_partial.id))
        end)
      end)

      describe("special cases", function()
        it("can render nested partials", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/page_pair",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(status, 200)
          assert.equals(1, stringx.count(body, auth_page_pair.id))
          assert.equals(1, stringx.count(body, nested_partial_parent.id))
          assert.equals(1, stringx.count(body, nested_partial_child.id))
        end)

        it("can avoid infinite loop partial references", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/infinite_loop_page",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(status, 200)
          assert.equals(1, stringx.count(body, infinite_loop_page.id))
          assert.equals(1, stringx.count(body, infinite_loop_partial.id))
          assert.equals(1, stringx.count(body, infinite_loop_partial.id))
        end)

        it("can handles partial formatting correctly", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/formatting_page",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(status, 200)
          assert.equals(1, stringx.count(body, formatting_page.id))
          assert.equals(1, stringx.count(body, block_syntax_partial.id))
          assert.equals(1, stringx.count(body, strange_spacing_partial.id))
          assert.equals(1, stringx.count(body, partial_with_argument.id))
          assert.equals(0, stringx.count(body, improper_format_partial.id))
        end)
      end)
    end)

    describe("specs", function()
      local root_spec_loader, auth_nested_spec_loader, unauth_nested_spec_loader,
            auth_spec1, auth_spec2, unauth_spec1, unauth_spec2,
            auth_nested_spec, unauth_nested_spec, login_page,
            spec_with_spaces

      lazy_setup(function()
        assert(register_developer({
          email = "catdog@konghq.com",
          key = "dog",
          meta = "{\"full_name\":\"catdog\"}",
        }))

        local res = api_client_request({method = "GET",
          path = "/auth",
          headers = {
            ['apikey'] = 'dog'
          }
        })
        cookie = assert.response(res).has.header("Set-Cookie")

        root_spec_loader = assert(db.files:insert {
          name = "loader",
          auth = true,
          type = "page",
          contents = [[
            <h1>root_spec_loader<h2>
          ]]
        })

        auth_nested_spec_loader = assert(db.files:insert {
          name = "abc/loader",
          auth = true,
          type = "page",
          contents = [[
            <h1>auth_nested_spec_loader<h2>
          ]]
        })

        unauth_nested_spec_loader = assert(db.files:insert {
          name = "unauthenticated/xyz/loader",
          auth = false,
          type = "page",
          contents = [[
            <h1>unauth_nested_spec_loader<h2>
          ]]
        })

        auth_spec1 = assert(db.files:insert {
          name = "auth_spec1",
          auth = true,
          type = "spec",
          contents = [[
            <h1>auth_spec1<h2>
          ]]
        })

        auth_spec2 = assert(db.files:insert {
          name = "auth_spec2",
          auth = true,
          type = "spec",
          contents = [[
            <h1>auth_spec2<h2>
          ]]
        })

        unauth_spec1 = assert(db.files:insert {
          name = "unauthenticated/unauth_spec1",
          auth = false,
          type = "spec",
          contents = [[
            <h1>unauth_spec1<h2>
          ]]
        })

        unauth_spec2 = assert(db.files:insert {
          name = "unauthenticated/unauth_spec2",
          auth = false,
          type = "spec",
          contents = [[
            <h1>unauth_spec2<h2>
          ]]
        })

        auth_nested_spec = assert(db.files:insert {
          name = "doggos/auth_nested_spec",
          auth = true,
          type = "spec",
          contents = [[
            <h1>auth_nested_spec<h2>
          ]]
        })

        unauth_nested_spec = assert(db.files:insert {
          name = "unauthenticated/floofs/unauth_nested_spec",
          auth = false,
          type = "spec",
          contents = [[
            <h1>unauth_nested_spec<h2>
          ]]
        })

        spec_with_spaces = assert(db.files:insert {
          name = "spec with spaces",
          auth = true,
          type = "spec",
          contents = [[
            <h1>spec with spaces<h2>
          ]]
        })

        login_page = assert(db.files:insert {
          name = "unauthenticated/login",
          auth = false,
          type = "page",
          contents = [[
            <h1>login<h2>
          ]]
        })
      end)

      lazy_teardown(function()
        db:truncate("files")
        -- db:truncate('consumers')
      end)

      describe("authenticated user", function()
        it("can render authenticated loader and authenticated specs", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/auth_spec1",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, root_spec_loader.id))
          assert.equals(1, stringx.count(body, auth_spec1.id))

          res = gui_client_request({
            method = "GET",
            path = "/default/auth_spec2",
            headers = {
              ["Cookie"] = cookie
            },
          })
          status = res.status
          body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, root_spec_loader.id))
          assert.equals(1, stringx.count(body, auth_spec2.id))
        end)

        it("can render authenticated loader and unauthenticated specs", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/unauth_spec1",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, root_spec_loader.id))
          assert.equals(1, stringx.count(body, unauth_spec1.id))

          res = gui_client_request({
            method = "GET",
            path = "/default/unauth_spec2",
            headers = {
              ["Cookie"] = cookie
            },
          })
          status = res.status
          body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, root_spec_loader.id))
          assert.equals(1, stringx.count(body, unauth_spec2.id))
        end)

        it("can render authenticated nested loader and authenticated specs", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/abc/auth_spec1",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, auth_nested_spec_loader.id))
          assert.equals(1, stringx.count(body, auth_spec1.id))

          res = gui_client_request({
            method = "GET",
            path = "/default/abc/auth_spec2",
            headers = {
              ["Cookie"] = cookie
            },
          })
          status = res.status
          body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, auth_nested_spec_loader.id))
          assert.equals(1, stringx.count(body, auth_spec2.id))
        end)

        it("can render authenticated nested loader and unauthenticated specs", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/abc/unauth_spec1",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, auth_nested_spec_loader.id))
          assert.equals(1, stringx.count(body, unauth_spec1.id))

          res = gui_client_request({
            method = "GET",
            path = "/default/abc/unauth_spec2",
            headers = {
              ["Cookie"] = cookie
            },
          })
          status = res.status
          body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, auth_nested_spec_loader.id))
          assert.equals(1, stringx.count(body, unauth_spec2.id))
        end)

        it("can render unauthenticated nested loader and unauthenticated specs", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/xyz/unauth_spec1",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, unauth_nested_spec_loader.id))
          assert.equals(1, stringx.count(body, unauth_spec1.id))

          res = gui_client_request({
            method = "GET",
            path = "/default/xyz/unauth_spec2",
            headers = {
              ["Cookie"] = cookie
            },
          })
          status = res.status
          body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, unauth_nested_spec_loader.id))
          assert.equals(1, stringx.count(body, unauth_spec2.id))
        end)

        it("can render authenticated nested loader and authenticated nested spec", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/abc/doggos/auth_nested_spec",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, auth_nested_spec_loader.id))
          assert.equals(1, stringx.count(body, auth_nested_spec.id))
        end)

        it("can render authenticated nested loader and unauthenticated nested spec", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/abc/floofs/unauth_nested_spec",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, auth_nested_spec_loader.id))
          assert.equals(1, stringx.count(body, unauth_nested_spec.id))
        end)

        it("can render unauthenticated nested loader and unauthenticated nested spec", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/xyz/floofs/unauth_nested_spec",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, unauth_nested_spec_loader.id))
          assert.equals(1, stringx.count(body, unauth_nested_spec.id))
        end)
      end)

      describe("unauthenticated user", function()
        it("can render unauthenticated nested loader and unauthenticated specs", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/xyz/unauth_spec1",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, unauth_nested_spec_loader.id))
          assert.equals(1, stringx.count(body, unauth_spec1.id))

          res = gui_client_request({
            method = "GET",
            path = "/default/xyz/unauth_spec2",
          })
          status = res.status
          body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, unauth_nested_spec_loader.id))
          assert.equals(1, stringx.count(body, unauth_spec2.id))
        end)

        it("cannot render authenticated loader and authenticated specs", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/auth_spec1",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, login_page.id))
          assert.equals(0, stringx.count(body, root_spec_loader.id))
          assert.equals(0, stringx.count(body, auth_spec1.id))

          res = gui_client_request({
            method = "GET",
            path = "/default/auth_spec2",
          })
          status = res.status
          body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, login_page.id))
          assert.equals(0, stringx.count(body, root_spec_loader.id))
          assert.equals(0, stringx.count(body, auth_spec2.id))
        end)

        it("cannot render unauthenticated nested loader and authenticated specs", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/xyz/auth_spec1",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, login_page.id))
          assert.equals(0, stringx.count(body, unauth_nested_spec_loader.id))
          assert.equals(0, stringx.count(body, unauth_spec1.id))

          res = gui_client_request({
            method = "GET",
            path = "/default/xyz/auth_spec2",
          })
          status = res.status
          body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, login_page.id))
          assert.equals(0, stringx.count(body, unauth_nested_spec_loader.id))
          assert.equals(0, stringx.count(body, unauth_spec2.id))
        end)

        it("cannot render unauthenticated nested loader and unauthenticated nested specs", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/xyz/floofs/unauth_nested_spec",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, unauth_nested_spec_loader.id))
          assert.equals(1, stringx.count(body, unauth_nested_spec.id))
        end)

        it("cannot render authenticated nested loader and authenticated nested specs", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/abc/doggos/auth_nested_spec",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, login_page.id))
          assert.equals(0, stringx.count(body, auth_nested_spec_loader.id))
          assert.equals(0, stringx.count(body, auth_nested_spec.id))
        end)

        it("cannot render unauthenticated nested loader and authenticated nested specs", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/xyz/doggos/auth_nested_spec",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, login_page.id))
          assert.equals(0, stringx.count(body, unauth_nested_spec_loader.id))
          assert.equals(0, stringx.count(body, auth_nested_spec.id))
        end)
      end)

      describe("special cases", function()
        it("can render spec with spaces in filename", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/spec%20with%20spaces",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, root_spec_loader.id))
          assert.equals(1, stringx.count(body, spec_with_spaces.id))
        end)
      end)
    end)

    describe("sitemap", function()
      lazy_setup(function()
        assert(register_developer({
          email = "catdog@konghq.com",
          key = "dog",
          meta = "{\"full_name\":\"catdog\"}",
        }))

        local res = api_client_request({method = "GET",
          path = "/auth",
          headers = {
            ['apikey'] = 'dog'
          }
        })
        cookie = assert.response(res).has.header("Set-Cookie")

        assert(db.files:insert {
          name = "page_pair",
          auth = true,
          type = "page",
          contents = [[
            <h1>auth_page_pair<h2>
          ]]
        })

        assert(db.files:insert {
          name = "unauthenticated/page_pair",
          auth = false,
          type = "page",
          contents = [[
            <h1>unauth_page_pair<h2>
          ]]
        })

        assert(db.files:insert {
          name = "auth_page_solo",
          auth = true,
          type = "page",
          contents = [[
            <h1>auth_page_solo<h2>
          ]]
        })

        assert(db.files:insert {
          name = "unauthenticated/unauth_page_solo",
          auth = false,
          type = "page",
          contents = [[
            <h1>unauth_page_solo<h2>
          ]]
        })

        assert(db.files:insert {
          name = "documentation/index",
          auth = true,
          type = "page",
          contents = [[
            <h1>auth index<h2>
          ]]
        })

        assert(db.files:insert {
          name = "unauthenticated/documentation/index",
          auth = true,
          type = "page",
          contents = [[
            <h1>index<h2>
          ]]
        })

        assert(db.files:insert {
          name = "unauthenticated/specs/loader",
          auth = true,
          type = "page",
          contents = [[
            <h1>loader<h2>
          ]]
        })

        assert(db.files:insert {
          name = "spec_page",
          auth = true,
          type = "spec",
          contents = [[
            {}
          ]]
        })

        assert(db.files:insert {
          name = "unauthenticated/spec_page",
          auth = false,
          type = "spec",
          contents = [[
            {}
          ]]
        })
      end)

      lazy_teardown(function()
        db:truncate("files")
        -- db:truncate('consumers')
      end)

      describe("authenticated user #test", function()
        it("can render sitemap for authenticated user", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/sitemap.xml",
            headers = {
              ["Cookie"] = cookie
            },
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, '/default/auth_page_solo'))
          assert.equals(1, stringx.count(body, '/default/documentation'))
          assert.equals(1, stringx.count(body, '/default/specs/spec_page'))
          assert.equals(1, stringx.count(body, '/default/unauth_page_solo'))
          assert.equals(1, stringx.count(body, '/default/page_pair'))
        end)
      end)

      describe("unauthenticated user", function()
        it("can render sitemap for unauthenticated user", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/sitemap.xml",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, '/default/page_pair'))
          assert.equals(1, stringx.count(body, '/default/unauth_page_solo'))
          assert.equals(0, stringx.count(body, '/default/auth_page_solo'))
          assert.equals(0, stringx.count(body, '/default/documentation'))
          assert.equals(0, stringx.count(body, '/default/specs/spec_page'))
        end)
      end)

      describe("special cases", function()
        it("can render default sitemap at root path", function()
          local res = gui_client_request({
            method = "GET",
            path = "/sitemap.xml",
          })
          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals(1, stringx.count(body, '/default/page_pair'))
          assert.equals(1, stringx.count(body, '/default/unauth_page_solo'))
          assert.equals(0, stringx.count(body, '/default/auth_page_solo'))
          assert.equals(0, stringx.count(body, '/default/documentation'))
          assert.equals(0, stringx.count(body, '/default/specs/spec_page'))
        end)
      end)
    end)
  end)
end
