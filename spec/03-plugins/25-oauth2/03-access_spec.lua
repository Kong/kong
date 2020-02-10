local cjson   = require "cjson"
local helpers = require "spec.helpers"
local utils   = require "kong.tools.utils"
local admin_api = require "spec.fixtures.admin_api"


local kong = {
  table = require("kong.pdk.table").new()
}


local function provision_code(host, extra_headers, client_id)
  local request_client = helpers.proxy_ssl_client()
  local res = assert(request_client:send {
    method = "POST",
    path = "/oauth2/authorize",
    body = {
      provision_key = "provision123",
      client_id = client_id or "clientid123",
      scope = "email",
      response_type = "code",
      state = "hello",
      authenticated_userid = "userid123"
    },
    headers = kong.table.merge({
      ["Host"] = host or "oauth2.com",
      ["Content-Type"] = "application/json"
    }, extra_headers)
  })
  assert.response(res).has.status(200)
  local body = assert.response(res).has.jsonbody()

  request_client:close()
  if body.redirect_uri then
    local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
    assert.is_nil(err)
    local m, err = iterator()
    assert.is_nil(err)
    return m[1]
  end
end


local function provision_token(host, extra_headers, client_id, client_secret)
  local code = provision_code(host, extra_headers, client_id)
  local request_client = helpers.proxy_ssl_client()
  local res = assert(request_client:send {
    method = "POST",
    path = "/oauth2/token",
    body = { code = code,
             client_id = client_id or "clientid123",
             client_secret = client_secret or "secret123",
             grant_type = "authorization_code" },
    headers = kong.table.merge({
      ["Host"] = host or "oauth2.com",
      ["Content-Type"] = "application/json"
    }, extra_headers)
  })
  assert.response(res).has.status(200)
  local token = assert.response(res).has.jsonbody()
  assert.is_table(token)
  request_client:close()
  return token
end


for _, strategy in helpers.each_strategy() do

describe("Plugin: oauth2 [#" .. strategy .. "]", function()
  local db

  lazy_setup(function()
    local _
    _, db = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "consumers",
      "plugins",
      "keyauth_credentials",
      "oauth2_credentials",
      "oauth2_authorization_codes",
      "oauth2_tokens",
    })

    assert(helpers.start_kong({
      database    = strategy,
      trusted_ips = "127.0.0.1",
      nginx_conf  = "spec/fixtures/custom_nginx.template",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  describe("access", function()
    local proxy_ssl_client
    local proxy_client
    local client1

    lazy_setup(function()

      local consumer = admin_api.consumers:insert {
        username = "bob"
      }

      local anonymous_user = admin_api.consumers:insert {
        username = "no-body"
      }

      client1 = admin_api.oauth2_credentials:insert {
        client_id      = "clientid123",
        client_secret  = "secret123",
        redirect_uris  = { "http://google.com/kong" },
        name           = "testapp",
        consumer       = { id = consumer.id },
      }

      admin_api.oauth2_credentials:insert {
        client_id      = "clientid789",
        client_secret  = "secret789",
        redirect_uris  = { "http://google.com/kong?foo=bar&code=123" },
        name           = "testapp2",
        consumer       = { id = consumer.id },
      }

      admin_api.oauth2_credentials:insert {
        client_id     = "clientid333",
        client_secret = "secret333",
        redirect_uris = { "http://google.com/kong" },
        name          = "testapp3",
        consumer      = { id = consumer.id },
      }

      admin_api.oauth2_credentials:insert {
        client_id     = "clientid456",
        client_secret = "secret456",
        redirect_uris = { "http://one.com/one/", "http://two.com/two" },
        name          = "testapp3",
        consumer      = { id = consumer.id },
      }

      admin_api.oauth2_credentials:insert {
        client_id     = "clientid1011",
        client_secret = "secret1011",
        redirect_uris = { "http://google.com/kong", },
        name          = "testapp31",
        consumer      = { id = consumer.id },
      }

      admin_api.oauth2_credentials:insert {
        client_id     = "clientid10112",
        client_secret = "secret10112",
        redirect_uris = ngx.null,
        name          = "testapp311",
        consumer      = { id = consumer.id },
      }

      local service1    = admin_api.services:insert()
      local service2    = admin_api.services:insert()
      local service2bis = admin_api.services:insert()
      local service3    = admin_api.services:insert()
      local service4    = admin_api.services:insert()
      local service5    = admin_api.services:insert()
      local service6    = admin_api.services:insert()
      local service7    = admin_api.services:insert()
      local service8    = admin_api.services:insert()
      local service9    = admin_api.services:insert()
      local service10   = admin_api.services:insert()
      local service11   = admin_api.services:insert()
      local service12   = admin_api.services:insert()
      local service13   = admin_api.services:insert()

      local route1 = assert(admin_api.routes:insert({
        hosts     = { "oauth2.com" },
        protocols = { "http", "https" },
        service   = service1,
      }))

      local route2 = assert(admin_api.routes:insert({
        hosts      = { "example-path.com" },
        protocols  = { "http", "https" },
        service    = service2,
      }))

      local route2bis = assert(admin_api.routes:insert({
        paths     = { "/somepath" },
        protocols = { "http", "https" },
        service   = service2bis,
      }))

      local route3 = assert(admin_api.routes:insert({
        hosts      = { "oauth2_3.com" },
        protocols  = { "http", "https" },
        service    = service3,
      }))

      local route4 = assert(admin_api.routes:insert({
        hosts      = { "oauth2_4.com" },
        protocols  = { "http", "https" },
        service    = service4,
      }))

      local route5 = assert(admin_api.routes:insert({
        hosts      = { "oauth2_5.com" },
        protocols  = { "http", "https" },
        service    = service5,
      }))

      local route6 = assert(admin_api.routes:insert({
        hosts      = { "oauth2_6.com" },
        protocols  = { "http", "https" },
        service    = service6,
      }))

      local route7 = assert(admin_api.routes:insert({
        hosts      = { "oauth2_7.com" },
        protocols  = { "http", "https" },
        service    = service7,
      }))

      local route8 = assert(admin_api.routes:insert({
        hosts      = { "oauth2_8.com" },
        protocols  = { "http", "https" },
        service    = service8,
      }))

      local route9 = assert(admin_api.routes:insert({
        hosts      = { "oauth2_9.com" },
        protocols  = { "http", "https" },
        service    = service9,
      }))

      local route10 = assert(admin_api.routes:insert({
        hosts       = { "oauth2_10.com" },
        protocols   = { "http", "https" },
        service     = service10,
      }))

      local route11 = assert(admin_api.routes:insert({
        hosts       = { "oauth2_11.com" },
        protocols   = { "http", "https" },
        service     = service11,
      }))

      local route12 = assert(admin_api.routes:insert({
        hosts       = { "oauth2_12.com" },
        protocols   = { "http", "https" },
        service     = service12,
      }))

      local route13 = assert(admin_api.routes:insert({
        hosts       = { "oauth2_13.com" },
        protocols   = { "http", "https" },
        service     = service13,
      }))

      admin_api.oauth2_plugins:insert({
        route = { id = route1.id },
        config   = { scopes = { "email", "profile", "user.email" } },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route2.id }
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route2bis.id }
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route3.id },
        config   = { hide_credentials = true },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route4.id },
        config   = {
          enable_client_credentials = true,
          enable_authorization_code = false,
        },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route5.id },
        config   = {
          enable_password_grant     = true,
          enable_authorization_code = false,
        },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route6.id },
        config   = {
          scopes                            = { "email", "profile", "user.email" },
          provision_key                     = "provision123",
          accept_http_if_already_terminated = true,
        },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route7.id },
        config   = {
          scopes    = { "email", "profile", "user.email" },
          anonymous = anonymous_user.id,
        },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route8.id },
        config   = {
          scopes             = { "email", "profile", "user.email" },
          global_credentials = true,
        },
      })


      admin_api.oauth2_plugins:insert({
        route = { id = route9.id },
        config   = {
          scopes             = { "email", "profile", "user.email" },
          global_credentials = true,
        },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route10.id },
        config   = {
          scopes             = { "email", "profile", "user.email" },
          global_credentials = true,
          anonymous          = utils.uuid(), -- a non existing consumer
        },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route11.id },
        config   = {
          scopes             = { "email", "profile", "user.email" },
          global_credentials = true,
          token_expiration   = 7,
          auth_header_name   = "custom_header_name",
        },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route12.id },
        config   = {
          scopes             = { "email", "profile", "user.email" },
          global_credentials = true,
          auth_header_name   = "custom_header_name",
          hide_credentials   = true,
        },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route13.id },
        config   = {
          scopes    = { "email", "profile", "user.email" },
          anonymous = anonymous_user.username,
        },
      })

      proxy_client     = helpers.proxy_client()
      proxy_ssl_client = helpers.proxy_ssl_client()
    end)

    lazy_teardown(function()
      if proxy_client and proxy_ssl_client then
        proxy_client:close()
        proxy_ssl_client:close()
      end
    end)

    describe("OAuth2 Authorization", function()
      describe("Code Grant", function()
        it("returns an error when no provision_key is being sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            headers = {
              ["Host"] = "oauth2.com"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Invalid provision_key", error = "invalid_provision_key" }, json)
          assert.are.equal("no-store", res.headers["cache-control"])
          assert.are.equal("no-cache", res.headers["pragma"])
        end)
        it("returns an error when no parameter is being sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key    = "provision123"
            },
            headers = {
              ["Host"]         = "oauth2.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Missing authenticated_userid parameter", error = "invalid_authenticated_userid" }, json)
        end)
        it("returns an error when only provision_key and authenticated_userid are sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123"
            },
            headers                = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
          assert.are.equal("no-store", res.headers["cache-control"])
          assert.are.equal("no-cache", res.headers["pragma"])
        end)
        it("returns an error when only the client_id is being sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ redirect_uri = "http://google.com/kong?error=invalid_scope&error_description=You%20must%20specify%20a%20scope" }, json)
        end)
        it("returns an error when an invalid scope is being sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "wot"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ redirect_uri = "http://google.com/kong?error=invalid_scope&error_description=%22wot%22%20is%20an%20invalid%20scope" }, json)
        end)
        it("returns an error when no response_type is being sent", function()
          local res = assert(proxy_ssl_client:send {
            method = "POST",
            path = "/oauth2/authorize",
            body = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "email"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ redirect_uri = "http://google.com/kong?error=unsupported_response_type&error_description=Invalid%20response_type" }, json)
        end)
        it("returns an error with a state when no response_type is being sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "email",
              state                = "somestate"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ redirect_uri = "http://google.com/kong?error=unsupported_response_type&error_description=Invalid%20response_type&state=somestate" }, json)
        end)
        it("returns error when the redirect_uri does not match", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "email",
              response_type        = "code",
              redirect_uri         = "http://hello.com/"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ redirect_uri = "http://google.com/kong?error=invalid_request&error_description=Invalid%20redirect_uri%20that%20does%20not%20match%20with%20any%20redirect_uri%20created%20with%20the%20application" }, json)
        end)
        it("works even if redirect_uri contains a query string", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key         = "provision123",
              authenticated_userid  = "id123",
              client_id             = "clientid789",
              scope                 = "email",
              response_type         = "code"
            },
            headers = {
              ["Host"]              = "oauth2_6.com",
              ["Content-Type"]      = "application/json",
              ["X-Forwarded-Proto"] = "https"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}&foo=bar$"))
        end)
        it("works with multiple redirect_uris in the application", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key         = "provision123",
              authenticated_userid  = "id123",
              client_id             = "clientid456",
              scope                 = "email",
              response_type         = "code"
            },
            headers = {
              ["Host"]              = "oauth2_6.com",
              ["Content-Type"]      = "application/json",
              ["X-Forwarded-Proto"] = "https"
            }
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          assert.truthy(ngx.re.match(json.redirect_uri, "^http://one\\.com/one/\\?code=[\\w]{32,32}$"))
        end)
        it("fails when not under HTTPS", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "email",
              response_type        = "code"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          assert.response(res).has.status(400)
          local json = assert.response(res).has.jsonbody(res)

          assert.equal("You must use HTTPS", json.error_description)
          assert.equal("access_denied", json.error)
        end)
        it("works when not under HTTPS but accept_http_if_already_terminated is true", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key         = "provision123",
              authenticated_userid  = "id123",
              client_id             = "clientid123",
              scope                 = "email",
              response_type         = "code"
            },
            headers = {
              ["Host"]              = "oauth2_6.com",
              ["Content-Type"]      = "application/json",
              ["X-Forwarded-Proto"] = "https"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}$"))
        end)
        it("fails when not under HTTPS and accept_http_if_already_terminated is false", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key         = "provision123",
              authenticated_userid  = "id123",
              client_id             = "clientid123",
              scope                 = "email",
              response_type         = "code"
            },
            headers = {
              ["Host"]              = "oauth2.com",
              ["Content-Type"]      = "application/json",
              ["X-Forwarded-Proto"] = "https"
            }
          })
          assert.response(res).has.status(400)
          local json = assert.response(res).has.jsonbody(res)

          assert.equal("You must use HTTPS", json.error_description)
          assert.equal("access_denied", json.error)
        end)
        it("returns success", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "email",
              response_type        = "code"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}$"))
        end)
        it("fails with a path when using the DNS", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123a",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "email",
              response_type        = "code",
            },
            headers = {
              ["Host"]             = "example-path.com",
              ["Content-Type"]     = "application/json",
            },
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Invalid provision_key", error = "invalid_provision_key" }, json)
        end)
        it("returns success with a path", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/somepath/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "email",
              response_type        = "code"
            },
            headers = {
              ["Content-Type"]     = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}$"))
        end)
        it("returns success when requesting the url with final slash", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize/",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "email",
              response_type        = "code"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}$"))
        end)
        it("returns success with a state", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "email",
              response_type        = "code",
              state                = "hello"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}&state=hello$"))
          -- Checking headers
          assert.are.equal("no-store", res.headers["cache-control"])
          assert.are.equal("no-cache", res.headers["pragma"])
        end)
        it("returns success and store authenticated user properties", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              client_id            = "clientid123",
              scope                = "email",
              response_type        = "code",
              state                = "hello",
              authenticated_userid = "userid123"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}&state=hello$"))

          local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
          assert.is_nil(err)
          local m, err = iterator()
          assert.is_nil(err)
          local data = db.oauth2_authorization_codes:select_by_code(m[1])
          assert.are.equal(m[1], data.code)
          assert.are.equal("userid123", data.authenticated_userid)
          assert.are.equal("email", data.scope)
          assert.are.equal(client1.id, data.credential.id)
        end)
        it("returns success with a dotted scope and store authenticated user properties", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              client_id            = "clientid123",
              scope                = "user.email",
              response_type        = "code",
              state                = "hello",
              authenticated_userid = "userid123"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}&state=hello$"))

          local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
          assert.is_nil(err)
          local m, err = iterator()
          assert.is_nil(err)
          local data = db.oauth2_authorization_codes:select_by_code(m[1])
          assert.are.equal(m[1], data.code)
          assert.are.equal("userid123", data.authenticated_userid)
          assert.are.equal("user.email", data.scope)
        end)
      end)

      describe("Implicit Grant", function()
        it("returns success", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "email",
              response_type        = "token"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\#access_token=[\\w]{32,32}&expires_in=[\\d]+&token_type=bearer$"))
          assert.are.equal("no-store", res.headers["cache-control"])
          assert.are.equal("no-cache", res.headers["pragma"])
        end)
        it("returns success and the state", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "email",
              response_type        = "token",
              state                = "wot"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\#access_token=[\\w]{32,32}&expires_in=[\\d]+&state=wot&token_type=bearer$"))
        end)
        it("returns success and the token should have the right expiration", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              scope                = "email",
              response_type        = "token"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\#access_token=[\\w]{32,32}&expires_in=[\\d]+&token_type=bearer$"))

          local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\#access_token=([\\w]{32,32})&expires_in=[\\d]+&token_type=bearer$")
          assert.is_nil(err)
          local m, err = iterator()
          assert.is_nil(err)
          local data = db.oauth2_tokens:select_by_access_token(m[1])
          assert.are.equal(m[1], data.access_token)
          assert.are.equal(5, data.expires_in)
          assert.falsy(data.refresh_token)
        end)
        it("returns success and store authenticated user properties", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              client_id            = "clientid123",
              scope                = "email  profile",
              response_type        = "token",
              authenticated_userid = "userid123"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\#access_token=[\\w]{32,32}&expires_in=[\\d]+&token_type=bearer$"))

          local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\#access_token=([\\w]{32,32})&expires_in=[\\d]+&token_type=bearer$")
          assert.is_nil(err)
          local m, err = iterator()
          assert.is_nil(err)
          local data = db.oauth2_tokens:select_by_access_token(m[1])
          assert.are.equal(m[1], data.access_token)
          assert.are.equal("userid123", data.authenticated_userid)
          assert.are.equal("email profile", data.scope)

          -- Checking that there is no refresh token since it's an implicit grant
          assert.are.equal(5, data.expires_in)
          assert.falsy(data.refresh_token)
        end)
        it("returns set the right upstream headers", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key        = "provision123",
              client_id            = "clientid123",
              scope                = "email  profile",
              response_type        = "token",
              authenticated_userid = "userid123"
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\#access_token=([\\w]{32,32})&expires_in=[\\d]+&token_type=bearer$")
          assert.is_nil(err)
          local m, err = iterator()
          assert.is_nil(err)
          local access_token = m[1]

          local res = assert(proxy_ssl_client:send {
            method  = "GET",
            path    = "/request?access_token=" .. access_token,
            headers = {
              ["Host"] = "oauth2.com"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.truthy(body.headers["x-consumer-id"])
          assert.are.equal("bob", body.headers["x-consumer-username"])
          assert.are.equal("email profile", body.headers["x-authenticated-scope"])
          assert.are.equal("userid123", body.headers["x-authenticated-userid"])
        end)
      end)

      describe("Client Credentials", function()
        it("returns an error when client_secret is not sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "clientid123",
              scope            = "email",
              response_type    = "token"
            },
            headers = {
              ["Host"]         = "oauth2_4.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
        end)
        it("returns an error when empty client_id and empty client_secret is sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "",
              client_secret    = "",
              scope            = "email",
              response_type    = "token",
              grant_type       = "client_credentials",
            },
            headers = {
              ["Host"]         = "oauth2_4.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
        end)
        it("returns an error when grant_type is not sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "clientid123",
              client_secret    = "secret123",
              scope            = "email",
              response_type    = "token"
            },
            headers = {
              ["Host"]         = "oauth2_4.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error = "unsupported_grant_type", error_description = "Invalid grant_type" }, json)
        end)
        it("fails when not under HTTPS", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "clientid123",
              client_secret    = "secret123",
              scope            = "email",
              grant_type       = "client_credentials"
            },
            headers = {
              ["Host"]         = "oauth2_4.com",
              ["Content-Type"] = "application/json"
            }
          })
          assert.response(res).has.status(400)
          local json = assert.response(res).has.jsonbody(res)

          assert.equal("You must use HTTPS", json.error_description)
          assert.equal("access_denied", json.error)
        end)
        it("fails when setting authenticated_userid and no provision_key", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id            = "clientid123",
              client_secret        = "secret123",
              scope                = "email",
              grant_type           = "client_credentials",
              authenticated_userid = "user123"
            },
            headers = {
              ["Host"]             = "oauth2_4.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Invalid provision_key", error = "invalid_provision_key" }, json)
        end)
        it("fails when setting authenticated_userid and invalid provision_key", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id            = "clientid123",
              client_secret        = "secret123",
              scope                = "email",
              grant_type           = "client_credentials",
              authenticated_userid = "user123",
              provision_key        = "hello"
            },
            headers = {
              ["Host"]             = "oauth2_4.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Invalid provision_key", error = "invalid_provision_key" }, json)
        end)
        it("returns success", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "clientid123",
              client_secret    = "secret123",
              scope            = "email",
              grant_type       = "client_credentials"
            },
            headers = {
              ["Host"]         = "oauth2_4.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          assert.is_table(ngx.re.match(body, [[^\{"token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
        end)
        it("returns success with an application that has multiple redirect_uri", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "clientid456",
              client_secret    = "secret456",
              scope            = "email",
              grant_type       = "client_credentials"
            },
            headers = {
              ["Host"]         = "oauth2_4.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          assert.is_table(ngx.re.match(body, [[^\{"token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
        end)
        it("returns success with an application that has multiple redirect_uri, and by passing a valid redirect_uri", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "clientid456",
              client_secret    = "secret456",
              scope            = "email",
              grant_type       = "client_credentials",
              redirect_uri     = "http://two.com/two"
            },
            headers = {
              ["Host"]         = "oauth2_4.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          assert.is_table(ngx.re.match(body, [[^\{"token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
        end)
        it("returns success with an application that has not redirect_uri", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "clientid10112",
              client_secret    = "secret10112",
              scope            = "email",
              grant_type       = "client_credentials",
            },
            headers = {
              ["Host"]         = "oauth2_4.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          assert.is_table(ngx.re.match(body, [[^\{"token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
        end)
        it("returns success with authenticated_userid and valid provision_key", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id            = "clientid123",
              client_secret        = "secret123",
              scope                = "email",
              grant_type           = "client_credentials",
              authenticated_userid = "hello",
              provision_key        = "provision123"
            },
            headers = {
              ["Host"]             = "oauth2_4.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          assert.is_table(ngx.re.match(body, [[^\{"token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
        end)
        it("returns success with authorization header", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              scope            = "email",
              grant_type       = "client_credentials"
            },
            headers = {
              ["Host"]         = "oauth2_4.com",
              ["Content-Type"] = "application/json",
              Authorization    = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTIz"
            }
          })
          local body = assert.res_status(200, res)
          assert.is_table(ngx.re.match(body, [[^\{"token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
        end)
        it("returns success with authorization header and client_id body param", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "clientid123",
              scope            = "email",
              grant_type       = "client_credentials"
            },
            headers = {
              ["Host"]         = "oauth2_4.com",
              ["Content-Type"] = "application/json",
              Authorization    = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTIz"
            }
          })
          local body = assert.res_status(200, res)
          assert.is_table(ngx.re.match(body, [[^\{"token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
        end)
        it("returns an error with a wrong authorization header", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              scope            = "email",
              grant_type       = "client_credentials"
            },
            headers = {
              ["Host"]         = "oauth2_4.com",
              ["Content-Type"] = "application/json",
              Authorization    = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTI0"
            }
          })
          local body = assert.res_status(401, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
          assert.are.equal("Basic realm=\"OAuth2.0\"", res.headers["www-authenticate"])
        end)
        it("sets the right upstream headers", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id            = "clientid123",
              client_secret        = "secret123",
              scope                = "email",
              grant_type           = "client_credentials",
              authenticated_userid = "hello",
              provision_key        = "provision123"
            },
            headers = {
              ["Host"]             = "oauth2_4.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))

          local res = assert(proxy_ssl_client:send {
            method  = "GET",
            path    = "/request?access_token=" .. body.access_token,
            headers = {
              ["Host"] = "oauth2_4.com"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.truthy(body.headers["x-consumer-id"])
          assert.are.equal("bob", body.headers["x-consumer-username"])
          assert.are.equal("email", body.headers["x-authenticated-scope"])
          assert.are.equal("hello", body.headers["x-authenticated-userid"])
        end)
        it("works in a multipart request", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id            = "clientid123",
              client_secret        = "secret123",
              scope                = "email",
              grant_type           = "client_credentials",
              authenticated_userid = "hello",
              provision_key        = "provision123"
            },
            headers = {
              ["Host"]             = "oauth2_4.com",
              ["Content-Type"]     = "multipart/form-data"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))

          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/request",
            body    = {
              access_token     = body.access_token
            },
            headers = {
              ["Host"]         = "oauth2_4.com",
              ["Content-Type"] = "multipart/form-data"
            }
          })
          assert.res_status(200, res)
        end)
      end)

      describe("Password Grant", function()
        it("blocks unauthorized requests", function()
          local res = assert(proxy_ssl_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              ["Host"] = "oauth2_5.com"
            }
          })
          local body = assert.res_status(401, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "The access token is missing", error = "invalid_request" }, json)
        end)
        it("returns an error when client_secret is not sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "clientid123",
              scope            = "email",
              response_type    = "token"
            },
            headers = {
              ["Host"]         = "oauth2_5.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
        end)
        it("returns an error when grant_type is not sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "clientid123",
              client_secret    = "secret123",
              scope            = "email",
              response_type    = "token"
            },
            headers = {
              ["Host"]         = "oauth2_5.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error = "unsupported_grant_type", error_description = "Invalid grant_type" }, json)
        end)
        it("fails when no provision key is being sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "clientid123",
              client_secret    = "secret123",
              scope            = "email",
              response_type    = "token",
              grant_type       = "password"
            },
            headers = {
              ["Host"]         = "oauth2_5.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Invalid provision_key", error = "invalid_provision_key" }, json)
        end)
        it("fails when no provision key is being sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              client_id        = "clientid123",
              client_secret    = "secret123",
              scope            = "email",
              grant_type       = "password"
            },
            headers = {
              ["Host"]         = "oauth2_5.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Invalid provision_key", error = "invalid_provision_key" }, json)
        end)
        it("fails when no authenticated user id is being sent", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              provision_key    = "provision123",
              client_id        = "clientid123",
              client_secret    = "secret123",
              scope            = "email",
              grant_type       = "password"
            },
            headers = {
              ["Host"]         = "oauth2_5.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Missing authenticated_userid parameter", error = "invalid_authenticated_userid" }, json)
        end)
        it("returns success", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              client_id            = "clientid123",
              client_secret        = "secret123",
              scope                = "email",
              grant_type           = "password"
            },
            headers = {
              ["Host"]             = "oauth2_5.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
        end)
        it("returns success with authorization header", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              scope                = "email",
              grant_type           = "password"
            },
            headers = {
              ["Host"]             = "oauth2_5.com",
              ["Content-Type"]     = "application/json",
              Authorization        = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTIz"
            }
          })
          local body = assert.res_status(200, res)
          assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
        end)
        it("returns an error with a wrong authorization header", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              scope                = "email",
              grant_type           = "password"
            },
            headers = {
              ["Host"]             = "oauth2_5.com",
              ["Content-Type"]     = "application/json",
              Authorization        = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTI0"
            }
          })
          local body = assert.res_status(401, res)
          local json = cjson.decode(body)
          assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
          assert.are.equal("Basic realm=\"OAuth2.0\"", res.headers["www-authenticate"])
        end)
        it("sets the right upstream headers", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              provision_key        = "provision123",
              authenticated_userid = "id123",
              scope                = "email",
              grant_type           = "password"
            },
            headers = {
              ["Host"]             = "oauth2_5.com",
              ["Content-Type"]     = "application/json",
              Authorization        = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTIz"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))

          local res = assert(proxy_ssl_client:send {
            method  = "GET",
            path    = "/request?access_token=" .. body.access_token,
            headers = {
              ["Host"] = "oauth2_5.com"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.truthy(body.headers["x-consumer-id"])
          assert.are.equal("bob", body.headers["x-consumer-username"])
          assert.are.equal("email", body.headers["x-authenticated-scope"])
          assert.are.equal("id123", body.headers["x-authenticated-userid"])
        end)
      end)
    end)

    describe("OAuth2 Access Token", function()
      it("returns an error when nothing is being sent", function()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          headers = {
            ["Host"] = "oauth2.com"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
        -- Checking headers
        assert.are.equal("no-store", res.headers["cache-control"])
        assert.are.equal("no-cache", res.headers["pragma"])
      end)
      it("returns an error when only the code is being sent", function()
        local code = provision_code()

        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
        -- Checking headers
        assert.are.equal("no-store", res.headers["cache-control"])
        assert.are.equal("no-cache", res.headers["pragma"])
      end)
      it("returns an error when only the code and client_secret are being sent", function()
        local code = provision_code()

        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_secret    = "secret123"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
        -- Checking headers
        assert.are.equal("no-store", res.headers["cache-control"])
        assert.are.equal("no-cache", res.headers["pragma"])
      end)
      it("returns an error when grant_type is not being sent", function()
        local code = provision_code()

        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            client_secret    = "secret123"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error = "unsupported_grant_type", error_description = "Invalid grant_type" }, json)
      end)
      it("returns an error with a wrong code", function()
        local code = provision_code()

        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code .. "hello",
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "authorization_code"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error = "invalid_request", error_description = "Invalid code" }, json)
      end)
      it("returns success without state", function()
        local code = provision_code()

        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code            = code,
            client_id       = "clientid123",
            client_secret   = "secret123",
            grant_type      = "authorization_code"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("returns success with state", function()
        local code = provision_code()

        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "authorization_code",
            state            = "wot"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","state":"wot","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("fails when the client used for the code is not the same client used for the token", function()
        local code = provision_code(nil, nil, "clientid333")

        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "authorization_code",
            state            = "wot"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        assert.same({ error = "invalid_request", error_description = "Invalid code", state = "wot" }, cjson.decode(body))
      end)
      it("sets the right upstream headers", function()
        local code = provision_code()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "authorization_code"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))

        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/request?access_token=" .. body.access_token,
          headers = {
            ["Host"] = "oauth2.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.truthy(body.headers["x-consumer-id"])
        assert.are.equal("bob", body.headers["x-consumer-username"])
        assert.are.equal("email", body.headers["x-authenticated-scope"])
        assert.are.equal("userid123", body.headers["x-authenticated-userid"])
      end)
      it("fails when an authorization code is used more than once", function()
        local code = provision_code()

        local res = assert(proxy_ssl_client:send {
            method = "POST",
            path   = "/oauth2/token",
            body   = {
              code             = code,
              client_id        = "clientid123",
              client_secret    = "secret123",
              grant_type       = "authorization_code"
            },
            headers = {
              ["Host"]         = "oauth2.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))

          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/token",
            body    = {
              code             = code,
              client_id        = "clientid123",
              client_secret    = "secret123",
              grant_type       = "authorization_code"
            },
            headers = {
              ["Host"]         = "oauth2.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error = "invalid_request", error_description = "Invalid code" }, json)
      end)
      it("fails when an authorization code is used by another application", function()
        local code = provision_code()
        local res = assert(proxy_ssl_client:send {
            method = "POST",
            path   = "/oauth2/token",
            body    = {
              code             = code,
              client_id        = "clientid789",
              client_secret    = "secret789",
              grant_type       = "authorization_code"
            },
            headers = {
              ["Host"]         = "oauth2.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ error = "invalid_request", error_description = "Invalid code" }, json)
      end)

      it("fails when an authorization code is used for another API", function()
        local code = provision_code()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "authorization_code"
          },
          headers = {
            ["Host"]         = "oauth2_3.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error = "invalid_request", error_description = "Invalid code" }, json)
      end)
    end)

    describe("Making a request", function()
      it("fails when no access_token is being sent in an application/json body", function()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "The access token is missing", error = "invalid_request" }, json)
      end)
      it("works when a correct access_token is being sent in the querystring", function()
        local token = provision_token()

        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/request?access_token=" .. token.access_token,
          headers = {
            ["Host"] = "oauth2.com"
          }
        })
        assert.res_status(200, res)
      end)
      it("works when a correct access_token is being sent in the custom header", function()
        local token = provision_token("oauth2_11.com",nil,"clientid1011","secret1011")

        local res = assert(proxy_ssl_client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "oauth2_11.com",
            ["custom_header_name"] = "bearer " .. token.access_token,
          }
        })
        assert.res_status(200, res)
      end)
      it("works when a correct access_token is being sent in duplicate custom headers", function()
        local token = provision_token("oauth2_11.com",nil,"clientid1011","secret1011")

        local res = assert(proxy_ssl_client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "oauth2_11.com",
            ["custom_header_name"] = { "bearer " .. token.access_token, "bearer " .. token.access_token },
          }
        })
        assert.res_status(200, res)
      end)
      it("fails when missing access_token is being sent in the custom header", function()
        local res = assert(proxy_ssl_client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "oauth2_11.com",
            ["custom_header_name"] = "",
          }
        })
        assert.res_status(401, res)
      end)
      it("fails when a correct access_token is being sent in the wrong header", function()
        local token = provision_token("oauth2_11.com",nil,"clientid1011","secret1011")

        local res = assert(proxy_ssl_client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "oauth2_11.com",
            ["authorization"] = "bearer " .. token.access_token,
          }
        })
        assert.res_status(401, res)
      end)
      it("does not work when requesting a different API", function()
        local token = provision_token()

        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/request?access_token=" .. token.access_token,
          headers = {
            ["Host"] = "oauth2_3.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "The access token is invalid or has expired", error = "invalid_token" }, json)
      end)
      it("works when a correct access_token is being sent in a form body", function()
        local token = provision_token()

        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            access_token     = token.access_token
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(200, res)
      end)
      it("does not throw an error when request has no body", function()
        -- Regression test for the following issue:
        -- https://github.com/Kong/kong/issues/3055
        --
        -- We want to make sure we do not attempt to parse a
        -- request body if the request isn't supposed to have
        -- once in the first place.

        -- setup: cleanup logs

        local test_error_log_path = helpers.test_conf.nginx_err_logs
        os.execute(":> " .. test_error_log_path)

        -- TEST: access with a GET request

        local token = provision_token()

        local res = assert(proxy_ssl_client:send {
          method = "GET",
          path = "/request?access_token=" .. token.access_token,
          headers = {
            ["Host"] = "oauth2.com"
          }
        })
        assert.res_status(200, res)

        -- Assertion: there should be no [error], including no error
        -- resulting from an invalid request body parsing that were
        -- previously thrown.

        local pl_file = require "pl.file"
        local logs = pl_file.read(test_error_log_path)

        for line in logs:gmatch("[^\r\n]+") do
          assert.not_match("[error]", line, nil, true)
        end
      end)
      it("works when a correct access_token is being sent in an authorization header (bearer)", function()
        local token = provision_token()

        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"]      = "oauth2.com",
            Authorization = "bearer " .. token.access_token
          }
        })
        assert.res_status(200, res)
      end)
      it("works when a correct access_token is being sent in an authorization header (token)", function()
        local token = provision_token()

        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"]      = "oauth2.com",
            Authorization = "bearer " .. token.access_token
          }
        })
        local body = cjson.decode(assert.res_status(200, res))

        local consumer = db.consumers:select_by_username("bob")
        assert.are.equal(consumer.id, body.headers["x-consumer-id"])
        assert.are.equal(consumer.username, body.headers["x-consumer-username"])
        assert.are.equal("userid123", body.headers["x-authenticated-userid"])
        assert.are.equal("email", body.headers["x-authenticated-scope"])
        assert.is_nil(body.headers["x-anonymous-consumer"])
      end)
      it("returns HTTP 400 when scope is not a string", function()
        local invalid_values = {
          { "email" },
          123,
          false,
        }

        for _, val in ipairs(invalid_values) do
          local res = assert(proxy_ssl_client:send {
            method = "POST",
            path = "/oauth2/token",
            body = {
              provision_key = "provision123",
              authenticated_userid = "id123",
              client_id = "clientid123",
              client_secret="secret123",
              scope = val,
              grant_type = "password",
            },
            headers = {
              ["Host"] = "oauth2_5.com",
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            error = "invalid_scope",
            error_description = "scope must be a string"
          }, json)
        end
      end)
      it("works with right credentials and anonymous", function()
        local token = provision_token("oauth2_7.com")
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"]      = "oauth2_7.com",
            Authorization = "bearer " .. token.access_token
          }
        })
        local body = cjson.decode(assert.res_status(200, res))

        local consumer = db.consumers:select_by_username("bob")
        assert.are.equal(consumer.id, body.headers["x-consumer-id"])
        assert.are.equal(consumer.username, body.headers["x-consumer-username"])
        assert.are.equal("userid123", body.headers["x-authenticated-userid"])
        assert.are.equal("email", body.headers["x-authenticated-scope"])
        assert.is_nil(body.headers["x-anonymous-consumer"])
      end)
      it("works with wrong credentials and anonymous", function()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"] = "oauth2_7.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.are.equal("true", body.headers["x-anonymous-consumer"])
        assert.equal('no-body', body.headers["x-consumer-username"])
      end)
      it("works with wrong credentials and username in anonymous", function()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"] = "oauth2_13.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.are.equal("true", body.headers["x-anonymous-consumer"])
        assert.equal('no-body', body.headers["x-consumer-username"])
      end)
      it("errors when anonymous user doesn't exist", function()
        finally(function()
          if proxy_ssl_client then
            proxy_ssl_client:close()
          end

          proxy_ssl_client = helpers.proxy_ssl_client()
        end)

        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "oauth2_10.com"
          }
        })
        assert.res_status(500, res)
      end)
      it("returns success and the token should have the right expiration when a custom header is passed", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid1011",
            scope = "email",
            response_type = "token"
          },
          headers = {
            ["Host"] = "oauth2_11.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\#access_token=[\\w]{32,32}&expires_in=[\\d]+&token_type=bearer$"))

        local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\#access_token=([\\w]{32,32})&expires_in=[\\d]+&token_type=bearer$")
        assert.is_nil(err)
        local m, err = iterator()
        assert.is_nil(err)
        local data = db.oauth2_tokens:select_by_access_token(m[1])
        assert.are.equal(m[1], data.access_token)
        assert.are.equal(7, data.expires_in)
        assert.falsy(data.refresh_token)
      end)
      describe("Global Credentials", function()
        it("does not access two different APIs that are not sharing global credentials", function()
          local token = provision_token("oauth2_8.com")

          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/request",
            headers = {
              ["Host"]      = "oauth2_8.com",
              Authorization = "bearer " .. token.access_token
            }
          })
          assert.res_status(200, res)

          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/request",
            headers = {
              ["Host"]      = "oauth2.com",
              Authorization = "bearer " .. token.access_token
            }
          })
          assert.res_status(401, res)
        end)
        it("does not access two different APIs that are not sharing global credentials 2", function()
          local token = provision_token("oauth2.com")

          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/request",
            headers = {
              ["Host"]      = "oauth2_8.com",
              Authorization = "bearer " .. token.access_token
            }
          })
          assert.res_status(401, res)

          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/request",
            headers = {
              ["Host"]      = "oauth2.com",
              Authorization = "bearer " .. token.access_token
            }
          })
          assert.res_status(200, res)
        end)
        it("access two different APIs that are sharing global credentials", function()
          local token = provision_token("oauth2_8.com")

          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/request",
            headers = {
              ["Host"]      = "oauth2_8.com",
              Authorization = "bearer " .. token.access_token
            }
          })
          assert.res_status(200, res)

          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/request",
            headers = {
              ["Host"]      = "oauth2_9.com",
              Authorization = "bearer " .. token.access_token
            }
          })
          assert.res_status(200, res)
        end)
      end)
    end)

    describe("Authentication challenge", function()
      it("returns 401 Unauthorized without error if it lacks any authentication information", function()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"] = "oauth2.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "The access token is missing", error = "invalid_request" }, json)
        assert.are.equal('Bearer realm="service"', res.headers['www-authenticate'])
      end)
      it("returns 401 Unauthorized when an invalid access token is being sent via url parameter", function()
        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/request?access_token=invalid",
          headers = {
            ["Host"] = "oauth2.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "The access token is invalid or has expired", error = "invalid_token" }, json)
        assert.are.equal('Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"', res.headers['www-authenticate'])
      end)
      it("returns 401 Unauthorized when an invalid access token is being sent via the Authorization header", function()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"]      = "oauth2.com",
            Authorization = "bearer invalid"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "The access token is invalid or has expired", error = "invalid_token" }, json)
        assert.are.equal('Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"', res.headers['www-authenticate'])
      end)
      it("returns 401 Unauthorized when token has expired", function()
        local token = provision_token()

        -- Token expires in 5 seconds
        local status, json, headers
        helpers.wait_until(function()
          local client = helpers.proxy_ssl_client()
          local res = assert(client:send {
            method  = "POST",
            path    = "/request",
            headers = {
              ["Host"]      = "oauth2.com",
              Authorization = "bearer " .. token.access_token
            }
          })
          local body = res:read_body()
          status = res.status
          headers = res.headers
          json = cjson.decode(body)
          client:close()
          return status == 401
        end, 7)
        assert.same({ error_description = "The access token is invalid or has expired", error = "invalid_token" }, json)
        assert.are.equal('Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"', headers['www-authenticate'])
      end)
    end)

    describe("Refresh Token", function()
      it("does not refresh an invalid access token", function()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            refresh_token    = "hello",
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "refresh_token"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error = "invalid_request", error_description = "Invalid refresh_token" }, json)
      end)
      it("refreshes an valid access token", function()
        local token = provision_token()

        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            refresh_token    = token.refresh_token,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "refresh_token"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("refreshes an valid access token and checks that it belongs to the application", function()
        local token = provision_token(nil, nil, "clientid333", "secret333")

        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            refresh_token    = token.refresh_token,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "refresh_token"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
        assert.are.equal("no-store", res.headers["cache-control"])
        assert.are.equal("no-cache", res.headers["pragma"])
      end)
      it("expires after 5 seconds", function()
        local token = provision_token()

        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"]      = "oauth2.com",
            authorization = "bearer " .. token.access_token
          }
        })
        assert.res_status(200, res)

        local id = db.oauth2_tokens:select_by_access_token(token.access_token).id
        assert.truthy(db.oauth2_tokens:select({ id = id }))

        -- But waiting after the cache expiration (5 seconds) should block the request
        local status, json
        helpers.wait_until(function()
          local client = helpers.proxy_client()
          local res = assert(client:send {
            method  = "POST",
            path    = "/request",
            headers = {
              ["Host"]      = "oauth2.com",
              authorization = "bearer " .. token.access_token
            }
          })
          status = res.status
          local body = res:read_body()
          json = body and cjson.decode(body)
          return status == 401
        end, 7)
        assert.same({ error_description = "The access token is invalid or has expired", error = "invalid_token" }, json)

        -- Refreshing the token
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            refresh_token    = token.refresh_token,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "refresh_token"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json",
            authorization    = "bearer " .. token.access_token
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))

        assert.falsy(token.access_token  == cjson.decode(body).access_token)
        assert.falsy(token.refresh_token == cjson.decode(body).refresh_token)

        assert.falsy(db.oauth2_tokens:select({ id = id }))
      end)
    end)

    describe("Hide Credentials", function()
      it("does not hide credentials in the body", function()
        local token = provision_token()

        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            access_token     = token.access_token
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(token.access_token, body.post_data.params.access_token)
      end)
      it("hides credentials in the body", function()
        local token = provision_token("oauth2_3.com")

        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            access_token     = token.access_token
          },
          headers = {
            ["Host"]         = "oauth2_3.com",
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_nil(body.post_data.params.access_token)
      end)
      it("does not hide credentials in the querystring", function()
        local token = provision_token()

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?access_token=" .. token.access_token,
          headers = {
            ["Host"] = "oauth2.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(token.access_token, body.uri_args.access_token)
      end)
      it("hides credentials in the querystring", function()
        local token = provision_token("oauth2_3.com")

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?access_token=" .. token.access_token,
          headers = {
            ["Host"] = "oauth2_3.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_nil(body.uri_args.access_token)
      end)
      it("hides credentials in the querystring for api with custom header", function()
        local token = provision_token("oauth2_12.com",nil,"clientid1011","secret1011")

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/request?access_token=" .. token.access_token,
          headers = {
            ["Host"] = "oauth2_12.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_nil(body.uri_args.access_token)
      end)
      it("does not hide credentials in the header", function()
        local token = provision_token()

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]      = "oauth2.com",
            authorization = "bearer " .. token.access_token
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("bearer " .. token.access_token, body.headers.authorization)
      end)
      it("hides credentials in the header", function()
        local token = provision_token("oauth2_3.com")

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]      = "oauth2_3.com",
            authorization = "bearer " .. token.access_token
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_nil(body.headers.authorization)
      end)
      it("hides credentials in the custom header", function()
        local token = provision_token("oauth2_12.com",nil,"clientid1011","secret1011")

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "oauth2_12.com",
            ["custom_header_name"] = "bearer " .. token.access_token
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_nil(body.headers.authorization)
        assert.is_nil(body.headers.custom_header_name)
      end)
      it("does not abort when the request body is a multipart form upload", function()
        local token = provision_token("oauth2_3.com")

        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request?access_token=" .. token.access_token,
          body    = {
            foo              = "bar"
          },
          headers = {
            ["Host"]         = "oauth2_3.com",
            ["Content-Type"] = "multipart/form-data"
          }
        })
        assert.res_status(200, res)
      end)
    end)
  end)


  describe("Plugin: oauth2 (access) [#" .. strategy .. "]", function()
    local proxy_client
    local user1
    local user2
    local anonymous

    lazy_setup(function()
      local service1 = admin_api.services:insert({
        path = "/request"
      })

      local route1 = assert(admin_api.routes:insert({
        hosts      = { "logical-and.com" },
        protocols  = { "http", "https" },
        service    = service1
      }))

      admin_api.oauth2_plugins:insert({
        route = { id = route1.id },
        config   = { scopes = { "email", "profile", "user.email" } },
      })

      admin_api.plugins:insert {
        name     = "key-auth",
        route = { id = route1.id },
      }

      anonymous = admin_api.consumers:insert {
        username = "Anonymous",
      }

      user1 = admin_api.consumers:insert {
        username = "Mickey",
      }

      user2 = admin_api.consumers:insert {
        username = "Aladdin",
      }

      local service2 = admin_api.services:insert({
        path = "/request"
      })

      local route2 = assert(admin_api.routes:insert({
        hosts      = { "logical-or.com" },
        protocols  = { "http", "https" },
        service    = service2
      }))

      admin_api.oauth2_plugins:insert({
        route = { id = route2.id },
        config   = {
          scopes    = { "email", "profile", "user.email" },
          anonymous = anonymous.id,
        },
      })

      admin_api.plugins:insert {
        name     = "key-auth",
        route = { id = route2.id },
        config   = {
          anonymous = anonymous.id,
        },
      }

      admin_api.keyauth_credentials:insert({
        key      = "Mouse",
        consumer = { id = user1.id },
      })

      admin_api.oauth2_credentials:insert {
        client_id      = "clientid4567",
        client_secret  = "secret4567",
        redirect_uris  = { "http://google.com/kong" },
        name           = "testapp",
        consumer       = { id = user2.id },
      }

      proxy_client = helpers.proxy_client()
    end)


    lazy_teardown(function()
      if proxy_client then proxy_client:close() end
    end)

    describe("multiple auth without anonymous, logical AND", function()

      it("passes with all credentials provided", function()
        local token = provision_token("logical-and.com",
          { ["apikey"] = "Mouse"}, "clientid4567", "secret4567").access_token
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers  = {
            ["Host"]          = "logical-and.com",
            ["apikey"]        = "Mouse",
            -- we must provide the apikey again in the extra_headers, for the
            -- token endpoint, because that endpoint is also protected by the
            -- key-auth plugin. Otherwise getting the token simply fails.
            ["Authorization"] = "bearer " .. token,
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.not_equal(id, anonymous.id)
        assert(id == user1.id or id == user2.id)
      end)

      it("fails 401, with only the first credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]   = "logical-and.com",
            ["apikey"] = "Mouse",
          }
        })
        assert.response(res).has.status(401)
      end)

      it("fails 401, with only the second credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]          = "logical-and.com",
            -- we must provide the apikey again in the extra_headers, for the
            -- token endpoint, because that endpoint is also protected by the
            -- key-auth plugin. Otherwise getting the token simply fails.
            ["Authorization"] = "bearer " .. provision_token("logical-and.com",
                  {["apikey"] = "Mouse"}).access_token,
          }
        })
        assert.response(res).has.status(401)
      end)

      it("fails 401, with no credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "logical-and.com",
          }
        })
        assert.response(res).has.status(401)
      end)

    end)

    describe("multiple auth with anonymous, logical OR", function()

      it("passes with all credentials provided", function()
        local token = provision_token("logical-or.com", nil,
                                      "clientid4567", "secret4567").access_token
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]          = "logical-or.com",
            ["apikey"]        = "Mouse",
            ["Authorization"] = "bearer " .. token,
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.not_equal(id, anonymous.id)
        assert(id == user1.id or id == user2.id)
      end)

      it("passes with only the first credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path = "/request",
          headers = {
            ["Host"] = "logical-or.com",
            ["apikey"] = "Mouse",
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.not_equal(id, anonymous.id)
        assert.equal(user1.id, id)
      end)

      it("passes with only the second credential provided", function()
        local token = provision_token("logical-or.com", nil,
                                      "clientid4567", "secret4567").access_token
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]          = "logical-or.com",
            ["Authorization"] = "bearer " .. token,
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.not_equal(id, anonymous.id)
        assert.equal(user2.id, id)
      end)

      it("passes with no credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "logical-or.com",
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.equal(id, anonymous.id)
      end)
    end)
  end)

  describe("Plugin: oauth2 (ttl) with #"..strategy, function()
    lazy_setup(function()
      local route11 = assert(admin_api.routes:insert({
        hosts     = { "oauth2_21.com" },
        protocols = { "http", "https" },
        service   = admin_api.services:insert(),
      }))

      admin_api.plugins:insert {
        name = "oauth2",
        route = { id = route11.id },
        config = {
          enable_authorization_code = true,
          mandatory_scope = false,
          provision_key = "provision123",
          global_credentials = false,
          refresh_token_ttl = 2
        }
      }

      local route12 = assert(admin_api.routes:insert({
        hosts     = { "oauth2_22.com" },
        protocols = { "http", "https" },
        service   = admin_api.services:insert(),
      }))

      admin_api.plugins:insert {
        name = "oauth2",
        route = { id = route12.id },
        config = {
          enable_authorization_code = true,
          mandatory_scope = false,
          provision_key = "provision123",
          global_credentials = false,
          refresh_token_ttl = 0
        }
      }

      local consumer = admin_api.consumers:insert {
        username = "bobo"
      }
      admin_api.oauth2_credentials:insert {
        client_id = "clientid7890",
        client_secret = "secret7890",
        redirect_uris = { "http://google.com/kong" },
        name = "testapp",
        consumer = { id = consumer.id },
      }
    end)

    describe("refresh token", function()
      it("is deleted after defined TTL", function()
        local token = provision_token("oauth2_21.com", nil, "clientid7890", "secret7890")
        local token_entity = db.oauth2_tokens:select_by_access_token(token.access_token)
        assert.is_table(token_entity)

        local err
        helpers.wait_until(function()
          token_entity, err = db.oauth2_tokens:select_by_access_token(token.access_token)
          return token_entity == nil and err == nil
        end, 3)
      end)

      it("is not deleted when when TTL is 0 == never", function()
        local token = provision_token("oauth2_22.com", nil, "clientid7890", "secret7890")
        local token_entity = db.oauth2_tokens:select_by_access_token(token.access_token)
        assert.is_table(token_entity)

        ngx.sleep(2.2)

        token_entity = db.oauth2_tokens:select_by_access_token(token.access_token)
        assert.is_table(token_entity)
      end)
    end)
  end)

  describe("Plugin: oauth2 regressions", function()
    it("responds 401 when using global token against non-global plugin", function()
      -- Regression test for issue:
      -- https://github.com/Kong/kong/issues/4232

      -- setup

      local route_token = assert(admin_api.routes:insert({
        hosts     = { "oauth2_regression_4232.com" },
        protocols = { "http", "https" },
        service   = admin_api.services:insert(),
      }))

      admin_api.plugins:insert {
        name = "oauth2",
        route = { id = route_token.id },
        config = {
          provision_key = "provision123",
          enable_authorization_code = true,
          global_credentials = true,
        }
      }

      local route_test = assert(admin_api.routes:insert({
        hosts     = { "oauth2_regression_4232_test.com" },
        protocols = { "http", "https" },
        service   = admin_api.services:insert(),
      }))

      admin_api.plugins:insert {
        name = "oauth2",
        route = { id = route_test.id },
        config = {
          enable_client_credentials = true,
          global_credentials = false,
        }
      }

      local consumer = admin_api.consumers:insert {
        username = "4232",
      }

      admin_api.oauth2_credentials:insert {
        client_id = "clientid_4232",
        client_secret = "secret_4232",
        redirect_uris = { "http://google.com/kong" },
        name = "4232_app",
        consumer = { id = consumer.id },
      }

      -- /setup

      local token = provision_token("oauth2_regression_4232.com", nil,
                                    "clientid_4232",
                                    "secret_4232")

      local proxy_ssl_client = helpers.proxy_ssl_client()

      local res = assert(proxy_ssl_client:send {
        method  = "POST",
        path    = "/anything",
        body    = {
          access_token = token.access_token
        },
        headers = {
          ["Host"]         = "oauth2_regression_4232_test.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(401, res)
      local json = cjson.decode(body)
      assert.same({
        error_description = "The access token is global, but the current " ..
                            "plugin is configured without 'global_credentials'",
        error = "invalid_token",
      }, json)
    end)
  end)
end)

end
