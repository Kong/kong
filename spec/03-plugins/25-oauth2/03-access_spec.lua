local cjson   = require "cjson"
local helpers = require "spec.helpers"
local utils   = require "kong.tools.utils"
local admin_api = require "spec.fixtures.admin_api"
local sha256 = require "resty.sha256"

local math_random = math.random
local string_char = string.char
local string_gsub = string.gsub
local string_rep = string.rep


local ngx_encode_base64 = ngx.encode_base64


local kong = {
  table = require("kong.pdk.table").new()
}


local function provision_code(host, extra_headers, client_id, code_challenge)
  local request_client = helpers.proxy_ssl_client()
  local body = {
      provision_key = "provision123",
      client_id = client_id or "clientid123",
      scope = "email",
      response_type = "code",
      state = "hello",
      authenticated_userid = "userid123",
  }
  if code_challenge then
    body["code_challenge"] = code_challenge
    body["code_method"] = "S256"
  end

  local res = assert(request_client:send {
    method = "POST",
    path = "/oauth2/authorize",
    body = body,
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


local function provision_token(host, extra_headers, client_id, client_secret, code_challenge, code_verifier, require_secret)
  local code = provision_code(host, extra_headers, client_id, code_challenge)
  local request_client = helpers.proxy_ssl_client()
  require_secret = require_secret == nil or require_secret
  local body = { code = code,
                 client_id = client_id or "clientid123",
                 grant_type = "authorization_code" }
  if client_secret or require_secret then
    body["client_secret"] = client_secret or "secret123"
  end
  if code_verifier then
    body["code_verifier"] = code_verifier
  end

  local res = assert(request_client:send {
    method = "POST",
    path = "/oauth2/token",
    body = body,
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


local function refresh_token(host, refresh_token)
  local request_client = helpers.proxy_ssl_client()
  local res = assert(request_client:send {
    method  = "POST",
    path    = "/oauth2/token",
    body    = {
      refresh_token    = refresh_token,
      client_id        = "clientid123",
      client_secret    = "secret123",
      grant_type       = "refresh_token"
    },
    headers = {
      ["Host"]         = host or "oauth2.com",
      ["Content-Type"] = "application/json"
    }
  })
  assert.response(res).has.status(200)
  local token = assert.response(res).has.jsonbody()
  assert.is_table(token)
  request_client:close()
  return token
end


local function get_pkce_tokens(code_verifier)
  if not code_verifier then
    code_verifier = ''
    for i = 1, 50 do
      code_verifier = code_verifier .. string_char(math_random(65, 90))
    end
  end
  local digest = sha256:new()
  digest:update(code_verifier)
  local code_challenge = ngx_encode_base64(digest:final(), true)
  code_challenge = string_gsub(code_challenge, "+", "-")
  code_challenge = string_gsub(code_challenge, "/", "_")
  return code_challenge, code_verifier
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
        hash_secret    = true,
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
        hash_secret   = true,
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
        hash_secret   = true,
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

      admin_api.oauth2_credentials:insert {
        client_id     = "clientid11211",
        client_secret = "secret11211",
        redirect_uris = { "http://google.com/kong", },
        name          = "testapp50",
        client_type   = "public",
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
      local service_c   = admin_api.services:insert()
      local service14   = admin_api.services:insert()
      local service15   = admin_api.services:insert()
      local service16   = admin_api.services:insert()

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

      local route_c = assert(admin_api.routes:insert({
        hosts       = { "oauth2__c.com" },
        protocols   = { "http", "https" },
        service     = service_c,
      }))

      local route14 = assert(admin_api.routes:insert({
        hosts       = { "oauth2_14.com" },
        protocols   = { "http", "https" },
        service     = service14,
      }))

      local route15 = assert(admin_api.routes:insert({
        hosts       = { "oauth2_15.com" },
        protocols   = { "http", "https" },
        service     = service15,
      }))

      local route16 = assert(admin_api.routes:insert({
        hosts       = { "oauth2_16.com" },
        protocols   = { "http", "https" },
        service     = service16,
      }))


      local service_grpc = assert(admin_api.services:insert {
          name = "grpc",
          url = "grpc://localhost:15002",
        })

      local route_grpc = assert(admin_api.routes:insert {
        protocols = { "grpc", "grpcs" },
        hosts     = { "oauth2_grpc.com" },
        paths = { "/hello.HelloService/SayHello" },
        service = service_grpc,
      })

      local route_provgrpc = assert(admin_api.routes:insert {
        hosts     = { "oauth2_grpc.com" },
        paths = { "/" },
        service = service_grpc,
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route_grpc.id },
        config   = {
          scopes = { "email", "profile", "user.email" },
        },
      })
      admin_api.oauth2_plugins:insert({
        route = { id = route_provgrpc.id },
        config   = {
          scopes = { "email", "profile", "user.email" },
        },
      })

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
          scopes                   = { "email", "profile", "user.email" },
          global_credentials       = true,
          reuse_refresh_token = true,
        },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route_c.id },
        config   = {
          scopes = { "email", "profile", "user.email" },
          anonymous = anonymous_user.username,
        },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route14.id },
        config   = {
          scopes                   = { "email", "profile", "user.email" },
          global_credentials       = true,
          pkce = "none",
        },
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route15.id },
        config   = {
          scopes                   = { "email", "profile", "user.email" },
          global_credentials       = true,
          pkce = "strict",
        }
      })

      admin_api.oauth2_plugins:insert({
        route = { id = route16.id },
        config   = {
          scopes                   = { "email", "profile", "user.email" },
          global_credentials       = true,
          pkce = "lax",
        }
      })
    end)

    before_each(function ()
      proxy_client     = helpers.proxy_client()
      proxy_ssl_client = helpers.proxy_ssl_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
      if proxy_ssl_client then proxy_ssl_client:close() end
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

        it("rejects gRPC call without credentials", function()
          local ok, err = helpers.proxy_client_grpcs(){
            service = "hello.HelloService.SayHello",
            opts = {
              ["-authority"] = "oauth2.com",
            },
          }
          assert.falsy(ok)
          assert.match("Code: Unauthenticated", err)
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
        it("fails when code challenge method is not supported", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key         = "provision123",
              client_id             = "clientid11211",
              scope                 = "user.email",
              response_type         = "code",
              state                 = "hello",
              authenticated_userid  = "userid123",
              code_challenge        = "1234",
              code_challenge_method = "foo",
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ redirect_uri = "http://google.com/kong?error=invalid_request&error_description=code_challenge_method%20is%20not%20supported%2c%20must%20be%20S256&state=hello" }, json)
        end)
        it("fails when code challenge method is provided without code challenge", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key         = "provision123",
              client_id             = "clientid11211",
              scope                 = "user.email",
              response_type         = "code",
              state                 = "hello",
              authenticated_userid  = "userid123",
              code_challenge_method = "H256",
            },
            headers = {
              ["Host"]              = "oauth2.com",
              ["Content-Type"]      = "application/json",
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ redirect_uri = "http://google.com/kong?error=invalid_request&error_description=code_challenge%20is%20required%20when%20code_method%20is%20present&state=hello" }, json)
        end)
        it("fails when code challenge is not included for public client", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key         = "provision123",
              client_id             = "clientid11211",
              scope                 = "user.email",
              response_type         = "code",
              state                 = "hello",
              authenticated_userid  = "userid123",
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ redirect_uri = "http://google.com/kong?error=invalid_request&error_description=code_challenge%20is%20required%20for%20public%20clients&state=hello" }, json)
        end)
        it("fails when code challenge is not included for confidential client when conf.pkce is strict", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key         = "provision123",
              client_id             = "clientid123",
              scope                 = "user.email",
              response_type         = "code",
              state                 = "hello",
              authenticated_userid  = "userid123",
            },
            headers = {
              ["Host"]             = "oauth2_15.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ redirect_uri = "http://google.com/kong?error=invalid_request&error_description=code_challenge%20is%20required%20for%20public%20clients&state=hello" }, json)
        end)
        it("returns success when code challenge is not included for public client when conf.pkce is none", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key         = "provision123",
              client_id             = "clientid11211",
              scope                 = "user.email",
              response_type         = "code",
              state                 = "hello",
              authenticated_userid  = "userid123",
            },
            headers = {
              ["Host"]             = "oauth2_14.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          local iterator, err = ngx.re.gmatch(json.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
          assert.is_nil(err)
          local m, err = iterator()
          assert.is_nil(err)
          db.oauth2_authorization_codes:select_by_code(m[1])
        end)
        it("returns success and defaults code method to S256 when not provided", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key         = "provision123",
              client_id             = "clientid11211",
              scope                 = "user.email",
              response_type         = "code",
              state                 = "hello",
              authenticated_userid  = "userid123",
              code_challenge        = "1234",
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          local iterator, err = ngx.re.gmatch(json.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
          assert.is_nil(err)
          local m, err = iterator()
          assert.is_nil(err)
          local data = db.oauth2_authorization_codes:select_by_code(m[1])
          assert.are.equal("1234", data.challenge)
          assert.are.equal("S256", data.challenge_method)
        end)
        it("returns success and saves code challenge", function()
          local res = assert(proxy_ssl_client:send {
            method  = "POST",
            path    = "/oauth2/authorize",
            body    = {
              provision_key         = "provision123",
              client_id             = "clientid11211",
              scope                 = "user.email",
              response_type         = "code",
              state                 = "hello",
              authenticated_userid  = "userid123",
              code_challenge        = "1234",
              code_challenge_method = "S256",
            },
            headers = {
              ["Host"]             = "oauth2.com",
              ["Content-Type"]     = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          local iterator, err = ngx.re.gmatch(json.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
          assert.is_nil(err)
          local m, err = iterator()
          assert.is_nil(err)
          local data = db.oauth2_authorization_codes:select_by_code(m[1])
          assert.are.equal("1234", data.challenge)
          assert.are.equal("S256", data.challenge_method)
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
          assert.are.equal("clientid123", body.headers["x-credential-identifier"])
          assert.are.equal(nil, body.headers["x-credential-username"])
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
          assert.are.equal("clientid123", body.headers["x-credential-identifier"])
          assert.are.equal(nil, body.headers["x-credential-username"])
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
          assert.are.equal("clientid123", body.headers["x-credential-identifier"])
          assert.are.equal(nil, body.headers["x-credential-username"])
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
        assert.are.equal("clientid123", body.headers["x-credential-identifier"])
        assert.are.equal(nil, body.headers["x-credential-username"])
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
      it("succeeds when using code challenge", function()
        local challenge, verifier = get_pkce_tokens()
        local code = provision_code(nil, nil, "clientid11211", challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code            = code,
            client_id       = "clientid11211",
            grant_type      = "authorization_code",
            code_verifier   = verifier
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("succeeds when authorization header used for public app", function()
        local challenge, verifier = get_pkce_tokens()
        local code = provision_code(nil, nil, "clientid11211", challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            grant_type       = "authorization_code",
            code_verifier    = verifier
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json",
            Authorization    = "Basic Y2xpZW50aWQxMTIxMQ=="
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("succeeds when authorization header used for public app with colon", function()
        local challenge, verifier = get_pkce_tokens()
        local code = provision_code(nil, nil, "clientid11211", challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            grant_type       = "authorization_code",
            code_verifier    = verifier
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json",
            Authorization    = "Basic Y2xpZW50aWQxMTIxMTo="
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("succeeds when authorization header used for public app with empty secret", function()
        local challenge, verifier = get_pkce_tokens()
        local code = provision_code(nil, nil, "clientid11211", challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            grant_type       = "authorization_code",
            code_verifier    = verifier
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json",
            Authorization    = "Basic Y2xpZW50aWQxMTIxMTogICAg"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("fails when a secret provided for public app", function()
        local challenge, verifier = get_pkce_tokens()
        local code = provision_code(nil, nil, "clientid11211", challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid11211",
            grant_type       = "authorization_code",
            code_verifier    = verifier,
            client_secret    = "secret11211"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "client_secret is disallowed for public clients", error = "invalid_request" }, json)
      end)
      it("fails when a secret provided for public app in header", function()
        local challenge, verifier = get_pkce_tokens()
        local code = provision_code(nil, nil, "clientid11211", challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            grant_type       = "authorization_code",
            code_verifier    = verifier,
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json",
            Authorization    = "Basic Y2xpZW50aWQxMTIxMTpzZWNyZXQxMTIxMQ=="
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "client_secret is disallowed for public clients", error = "invalid_request" }, json)
      end)
      it("fails when no code_verifier provided for public app", function()
        local challenge, _ = get_pkce_tokens()
        local code = provision_code(nil, nil, "clientid11211", challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid11211",
            grant_type       = "authorization_code",
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "code_verifier is required for PKCE authorization requests", error = "invalid_request" }, json)
      end)
      it("success when no code_verifier provided for public app without pkce when conf.pkce is none", function()
        local code = provision_code()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "authorization_code",
          },
          headers = {
            ["Host"]         = "oauth2_14.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("success when code challenge contains padding", function()
        local code_verifier = "abcdelfhigklmnopqrstuvwxyz0123456789abcdefg"
        local code_challenge = "2aC4cMSkAsMRtZbhHhiZkDW3sddRf_iTRGil1r9gi8w="
        local code = provision_code(nil, nil, "clientid11211", code_challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid11211",
            grant_type       = "authorization_code",
            code_verifier    = code_verifier
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("succeeds when code challenge contains + or / characters", function()
        local code_verifier = "abcdelfhigklmnopqrstuvwxyz0123456789abcdefghijklmnop9"
        local code_challenge = "0LoS6Gtrw16r07+ZXsCf8MeAi21QHmKc3LJdUCA5w/o="
        local code = provision_code(nil, nil, "clientid11211", code_challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid11211",
            grant_type       = "authorization_code",
            code_verifier    = code_verifier
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("fails when code verifier is greater than 128 characters", function()
        local code_verifier = string_rep("abc123", 30)
        local challenge, verifier = get_pkce_tokens(code_verifier)
        local code = provision_code(nil, nil, "clientid11211", challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid11211",
            grant_type       = "authorization_code",
            code_verifier    = verifier
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "code_verifier must be between 43 and 128 characters", error = "invalid_request" }, json)
      end)
      it("fails when code verifier is less than 43 characters", function()
        local challenge, verifier = get_pkce_tokens("abc123")
        local code = provision_code(nil, nil, "clientid11211", challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body          = {
            code             = code,
            client_id        = "clientid11211",
            grant_type       = "authorization_code",
            code_verifier    = verifier
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "code_verifier must be between 43 and 128 characters", error = "invalid_request" }, json)
      end)
      it("fails when code verifier is missing", function()
        local challenge, _ = get_pkce_tokens("abc123")
        local code = provision_code(nil, nil, "clientid11211", challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body          = {
            code             = code,
            client_id        = "clientid11211",
            grant_type       = "authorization_code",
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "code_verifier is required for PKCE authorization requests", error = "invalid_request" }, json)
      end)
      it("fails when secret does not match for non-authorization_code grant type", function()
        local challenge, _ = get_pkce_tokens()
        local code = provision_code(nil, nil, "clientid11211", challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            provision_key        = "provision123",
            authenticated_userid = "id123",
            client_id            = "clientid123",
            scope                = "email",
            grant_type           = "password",
            client_secret        = "bogus",
            code                 = code
          },
          headers = {
            ["Host"]             = "oauth2_5.com",
            ["Content-Type"]     = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
      end)
      it("fails when code verifier is empty", function()
        local code = provision_code(nil, nil, "clientid11211", "abc123")
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid11211",
            grant_type       = "authorization_code",
            code_verifier    = ""
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "code_verifier must be between 43 and 128 characters", error = "invalid_request" }, json)
      end)
      it("fails when code verifier is not a string", function()
        local code = provision_code(nil, nil, "clientid11211", "abc123")
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid11211",
            grant_type       = "authorization_code",
            code_verifier    = 12
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "code_verifier is not a string", error = "invalid_request" }, json)
      end)
      it("fails when code verifier does not match challenge", function()
        local code = provision_code(nil, nil, "clientid11211", "abc123")
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid11211",
            grant_type       = "authorization_code",
            code_verifier    = "abcdelfhigklmnopqrstuvwxyz0123456789abcdefg"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid code", error = "invalid_grant" }, json)
      end)
      it("fails when code verifier does not match challenge for confidential app when conf.pkce is strict", function()
        local challenge, _ = get_pkce_tokens()
        local code = provision_code(nil, nil, nil, challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "authorization_code",
            code_verifier    = "abcdelfhigklmnopqrstuvwxyz0123456789abcdefg"
          },
          headers = {
            ["Host"]         = "oauth2_15.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid code", error = "invalid_grant" }, json)
      end)
      it("fails when wrong auth code provided for public app", function()
        local challenge, verifier = get_pkce_tokens()
        local code = provision_code(nil, nil, "clientid11211", challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code .. "hello",
            client_id        = "clientid11211",
            grant_type       = "authorization_code",
            code_verifier    = verifier,
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid code", error = "invalid_request" }, json)
      end)
      it("fails when no auth code provided for public app", function()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            client_id        = "clientid11211",
            grant_type       = "authorization_code",
            code_verifier    = "verifier",
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid code", error = "invalid_request" }, json)
      end)
      it("fails when no secret provided for confidential app", function()
        local code = provision_code()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            grant_type       = "authorization_code",
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
      end)
      it("fails when no code verifier provided for confidential app when conf.pkce is strict", function()
        local code = provision_code()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "authorization_code",
          },
          headers = {
            ["Host"]         = "oauth2_15.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "code_verifier is required for PKCE authorization requests", error = "invalid_request" }, json)
      end)
      it("fails when no code verifier provided for confidential app with pkce when conf.pkce is lax", function()
        local challenge, _ = get_pkce_tokens()
        local code = provision_code(nil, nil, nil, challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "authorization_code",
          },
          headers = {
            ["Host"]         = "oauth2_16.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "code_verifier is required for PKCE authorization requests", error = "invalid_request" }, json)
      end)
      it("fails when no code verifier provided for confidential app with pkce when conf.pkce is none", function()
        local challenge, _ = get_pkce_tokens()
        local code = provision_code(nil, nil, nil, challenge)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "authorization_code",
          },
          headers = {
            ["Host"]         = "oauth2_14.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "code_verifier is required for PKCE authorization requests", error = "invalid_request" }, json)
      end)
      it("suceeds when no code verifier provided for confidential app without pkce when conf.pkce is none", function()
        local code = provision_code()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "authorization_code",
          },
          headers = {
            ["Host"]         = "oauth2_14.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("suceeds when no code verifier provided for confidential app without pkce when conf.pkce is lax", function()
        local code = provision_code()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            code             = code,
            client_id        = "clientid123",
            client_secret    = "secret123",
            grant_type       = "authorization_code",
          },
          headers = {
            ["Host"]         = "oauth2_16.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
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
        assert.are.equal("clientid123", body.headers["x-credential-identifier"])
        assert.are.equal(nil, body.headers["x-credential-username"])
        assert.is_nil(body.headers["x-anonymous-consumer"])
      end)

      it("accepts gRPC call with credentials", function()
        local token = provision_token("oauth2_grpc.com")

        local ok, res = helpers.proxy_client_grpcs(){
          service = "hello.HelloService.SayHello",
          opts = {
            ["-authority"] = "oauth2_grpc.com",
            ["-H"] = ("'authorization: bearer %s'"):format(token.access_token),
          },
        }
        assert.truthy(ok)
        assert.same({ reply = "hello noname" }, cjson.decode(res))
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
        assert.are.equal("clientid123", body.headers["x-credential-identifier"])
        assert.are.equal(nil, body.headers["x-credential-username"])
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
        assert.are.equal(nil, body.headers["x-credential-identifier"])
        assert.are.equal(nil, body.headers["x-credential-username"])

      end)
      it("works with wrong credentials and username in anonymous", function()
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/request",
          headers = {
            ["Host"] = "oauth2__c.com"
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
      it("refreshes public app without a secret", function()
        local challenge, verifier = get_pkce_tokens()
        local token = provision_token(nil, nil, "clientid11211", nil, challenge, verifier, false)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            refresh_token    = token.refresh_token,
            client_id        = "clientid11211",
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
      it("fails to refresh when a secret provided for public app", function()
        local challenge, verifier = get_pkce_tokens()
        local token = provision_token(nil, nil, "clientid11211", nil, challenge, verifier, false)
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            refresh_token    = token.refresh_token,
            client_id        = "clientid11211",
            client_secret    = "secret11211",
            grant_type       = "refresh_token"
          },
          headers = {
            ["Host"]         = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "client_secret is disallowed for public clients", error = "invalid_request" }, json)
      end)
      it("fails to refresh when no secret provided for confidential app", function()
        local token = provision_token(nil, nil, "clientid123")
        local res = assert(proxy_ssl_client:send {
          method  = "POST",
          path    = "/oauth2/token",
          body    = {
            refresh_token    = token.refresh_token,
            client_id        = "clientid123",
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
      it("does rewrite non-persistent refresh tokens", function ()
        local token = provision_token()
        local refreshed_token = refresh_token(nil, token.refresh_token)
        assert.is_table(refreshed_token)
        assert.falsy(token.refresh_token == refreshed_token.refresh_token)
      end)
      it("does not rewrite persistent refresh tokens", function()
        local token = provision_token("oauth2_13.com")
        local refreshed_token = refresh_token("oauth2_13.com", token.refresh_token)
        local new_access_token = db.oauth2_tokens:select_by_access_token(refreshed_token.access_token)
        local new_refresh_token = db.oauth2_tokens:select_by_refresh_token(token.refresh_token)
        assert.truthy(new_refresh_token)
        assert.same(new_access_token.id, new_refresh_token.id)


        -- check refreshing sets created_at so access token doesn't expire
        db.oauth2_tokens:update({
          id = new_refresh_token.id
        }, {
          created_at = 123, -- set time as expired
        })

        local status, json, headers
        helpers.wait_until(function()
          local client = helpers.proxy_ssl_client()
          local first_res = assert(client:send {
            method  = "POST",
            path    = "/request",
            headers = {
              ["Host"]      = "oauth2_13.com",
              Authorization = "bearer " .. refreshed_token.access_token
            }
          })
          local nbody = first_res:read_body()
          status = first_res.status
          headers = first_res.headers
          json = cjson.decode(nbody)
          client:close()
          return status == 401
        end, 7)
        assert.same({ error_description = "The access token is invalid or has expired", error = "invalid_token" }, json)
        assert.are.equal('Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"', headers['www-authenticate'])

        local final_refreshed_token = refresh_token("oauth2_13.com", refreshed_token.refresh_token)
        local last_res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]      = "oauth2_13.com",
            authorization = "bearer " .. final_refreshed_token.access_token
          }
        })
        local last_body = cjson.decode(assert.res_status(200, last_res))
        assert.equal("bearer " .. final_refreshed_token.access_token, last_body.headers.authorization)

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
    local keyauth

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

      keyauth = admin_api.keyauth_credentials:insert({
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

        local client_id = assert.request(res).has.header("x-credential-identifier")
        assert.equal(keyauth.id, client_id)
        assert.request(res).has.no.header("x-credential-username")
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
        local client_id = assert.request(res).has.header("x-credential-identifier")
        assert.equal("clientid4567", client_id)
        assert.request(res).has.no.header("x-credential-username")
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
        local client_id = assert.request(res).has.header("x-credential-identifier")
        assert.equal(keyauth.id, client_id)
        assert.request(res).has.no.header("x-credential-username")
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
        local client_id = assert.request(res).has.header("x-credential-identifier")
        assert.equal("clientid4567", client_id)
        assert.request(res).has.no.header("x-credential-username")
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
        assert.request(res).has.no.header("x-credential-identifier")
        assert.request(res).has.no.header("x-credential-username")
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
