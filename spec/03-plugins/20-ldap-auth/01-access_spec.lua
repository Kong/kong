local helpers = require "spec.helpers"
local utils   = require "kong.tools.utils"


local lower   = string.lower
local fmt     = string.format
local md5     = ngx.md5


local function cache_key(conf, username, password)
  local prefix = md5(fmt("%s:%u:%s:%s:%u",
    lower(conf.ldap_host),
    conf.ldap_port,
    conf.base_dn,
    conf.attribute,
    conf.cache_ttl
  ))

  return fmt("ldap_auth_cache:%s:%s:%s", prefix, username, password)
end


local ldap_host_aws = "ec2-54-172-82-117.compute-1.amazonaws.com"

local ldap_strategies = {
  non_secure = { name = "non-secure", start_tls = false },
  start_tls = { name = "starttls", start_tls = true }
}

for _, ldap_strategy in pairs(ldap_strategies) do
  describe("Connection strategy [" .. ldap_strategy.name .. "]", function()
    for _, strategy in helpers.each_strategy() do
      describe("Plugin: ldap-auth (access) [#" .. strategy .. "]", function()
        local proxy_client
        local admin_client
        local route2
        local plugin2

        lazy_setup(function()
          local bp = helpers.get_db_utils(strategy, {
            "routes",
            "services",
            "plugins",
            "consumers",
          })

          local route1 = bp.routes:insert {
            hosts = { "ldap.com" },
          }

          route2 = bp.routes:insert {
            hosts = { "ldap2.com" },
          }

          local route3 = bp.routes:insert {
            hosts = { "ldap3.com" },
          }

          local route4 = bp.routes:insert {
            hosts = { "ldap4.com" },
          }

          local route5 = bp.routes:insert {
            hosts = { "ldap5.com" },
          }

          bp.routes:insert {
            hosts = { "ldap6.com" },
          }

          local route7 = bp.routes:insert {
            hosts = { "ldap7.com" },
          }

          local anonymous_user = bp.consumers:insert {
            username = "no-body"
          }

          bp.plugins:insert {
            route = { id = route1.id },
            name     = "ldap-auth",
            config   = {
              ldap_host = ldap_host_aws,
              ldap_port = 389,
              start_tls = ldap_strategy.start_tls,
              base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
              attribute = "uid"
            }
          }

          plugin2 = bp.plugins:insert {
            route = { id = route2.id },
            name     = "ldap-auth",
            config   = {
              ldap_host        = ldap_host_aws,
              ldap_port        = 389,
              start_tls        = ldap_strategy.start_tls,
              base_dn          = "ou=scientists,dc=ldap,dc=mashape,dc=com",
              attribute        = "uid",
              hide_credentials = true,
              cache_ttl        = 2,
            }
          }

          bp.plugins:insert {
            route = { id = route3.id },
            name     = "ldap-auth",
            config   = {
              ldap_host = ldap_host_aws,
              ldap_port = 389,
              start_tls = ldap_strategy.start_tls,
              base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
              attribute = "uid",
              anonymous = anonymous_user.id,
            }
          }

          bp.plugins:insert {
            route = { id = route4.id },
            name     = "ldap-auth",
            config   = {
              ldap_host = "ec2-54-210-29-167.compute-1.amazonaws.com",
              ldap_port = 389,
              start_tls = ldap_strategy.start_tls,
              base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
              attribute = "uid",
              cache_ttl = 2,
              anonymous = utils.uuid(), -- non existing consumer
            }
          }

          bp.plugins:insert {
            route = { id = route5.id },
            name     = "ldap-auth",
            config   = {
              ldap_host = ldap_host_aws,
              ldap_port = 389,
              start_tls = ldap_strategy.start_tls,
              base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
              attribute = "uid",
              header_type = "Basic",
            }
          }

          bp.plugins:insert {
            name     = "ldap-auth",
            config   = {
              ldap_host = ldap_host_aws,
              ldap_port = 389,
              start_tls = ldap_strategy.start_tls,
              base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
              attribute = "uid"
            }
          }

          bp.plugins:insert {
            route = { id = route7.id },
            name     = "ldap-auth",
            config   = {
              ldap_host = ldap_host_aws,
              ldap_port = 389,
              start_tls = ldap_strategy.start_tls,
              base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
              attribute = "uid",
              anonymous = anonymous_user.username,
            }
          }

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          }))
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        before_each(function()
          proxy_client = helpers.proxy_client()
          admin_client = helpers.admin_client()
        end)

        after_each(function()
          if proxy_client then
            proxy_client:close()
          end

          if admin_client then
            admin_client:close()
          end
        end)

        it("returns 'invalid credentials' and www-authenticate header when the credential is missing", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              host  = "ldap.com"
            }
          })
          assert.response(res).has.status(401)
          local value = assert.response(res).has.header("www-authenticate")
          assert.are.equal('LDAP realm="kong"', value)
          local json = assert.response(res).has.jsonbody()
          assert.equal("Unauthorized", json.message)
        end)
        it("returns 'invalid credentials' when credential value is in wrong format in authorization header", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              host  = "ldap.com",
              authorization = "abcd"
            }
          })
          assert.response(res).has.status(401)
          local json = assert.response(res).has.jsonbody()
          assert.equal("Invalid authentication credentials", json.message)
        end)
        it("returns 'invalid credentials' when credential value is in wrong format in proxy-authorization header", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              host  = "ldap.com",
              ["proxy-authorization"] = "abcd"
            }
          })
          assert.response(res).has.status(401)
          local json = assert.response(res).has.jsonbody()
          assert.equal("Invalid authentication credentials", json.message)
        end)
        it("returns 'invalid credentials' when credential value is missing in authorization header", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              host          = "ldap.com",
              authorization = "ldap "
            }
          })
          assert.response(res).has.status(401)
          local json = assert.response(res).has.jsonbody()
          assert.equal("Invalid authentication credentials", json.message)
        end)
        it("passes if credential is valid in post request", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/request",
            body    = {},
            headers = {
              host             = "ldap.com",
              authorization    = "ldap " .. ngx.encode_base64("einstein:password"),
              ["content-type"] = "application/x-www-form-urlencoded",
            }
          })
          assert.response(res).has.status(200)
        end)
        it("fails if credential type is invalid in post request", function()
          local r = assert(proxy_client:send {
            method = "POST",
            path = "/request",
            body = {},
            headers = {
              host = "ldap.com",
              authorization = "invalidldap " .. ngx.encode_base64("einstein:password"),
              ["content-type"] = "application/x-www-form-urlencoded",
            }
          })
          assert.response(r).has.status(401)
        end)
        it("passes if credential is valid and starts with space in post request", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/request",
            headers = {
              host          = "ldap.com",
              authorization = " ldap " .. ngx.encode_base64("einstein:password")
            }
          })
          assert.response(res).has.status(200)
        end)
        it("passes if signature type indicator is in caps and credential is valid in post request", function()
          local res = assert(proxy_client:send {
            method  = "POST",
            path    = "/request",
            headers = {
              host          = "ldap.com",
              authorization = "LDAP " .. ngx.encode_base64("einstein:password")
            }
          })
          assert.response(res).has.status(200)
        end)
        it("passes if credential is valid in get request", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              host          = "ldap.com",
              authorization = "ldap " .. ngx.encode_base64("einstein:password")
            }
          })
          assert.response(res).has.status(200)
          local value = assert.request(res).has.header("x-credential-username")
          assert.are.equal("einstein", value)
          assert.request(res).has_not.header("x-anonymous-username")
        end)
        it("authorization fails if credential does has no password encoded in get request", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              host          = "ldap.com",
              authorization = "ldap " .. ngx.encode_base64("einstein:")
            }
          })
          assert.response(res).has.status(401)
        end)
        it("authorization fails with correct status with wrong very long password", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              host          = "ldap.com",
              authorization = "ldap " .. ngx.encode_base64("einstein:e0d91f53c566e0d91f53c566e0d91f53c566e0d91f53c566e0d91f53c566e0d91f53c566e0d91f53c566e0d91f53c566e0d91f53c566e0d91f53c566e0d91f53c566e0d91f53c566e0d91f53c566")
            }
          })
          assert.response(res).has.status(401)
        end)
        it("authorization fails if credential has multiple encoded usernames or passwords separated by ':' in get request", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              host          = "ldap.com",
              authorization = "ldap " .. ngx.encode_base64("einstein:password:another_password")
            }
          })
          assert.response(res).has.status(401)
        end)
        it("does not pass if credential is invalid in get request", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              host          = "ldap.com",
              authorization = "ldap " .. ngx.encode_base64("einstein:wrong_password")
            }
          })
          assert.response(res).has.status(401)
        end)
        it("does not hide credential sent along with authorization header to upstream server", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              host          = "ldap.com",
              authorization = "ldap " .. ngx.encode_base64("einstein:password")
            }
          })
          assert.response(res).has.status(200)
          local value = assert.request(res).has.header("authorization")
          assert.equal("ldap " .. ngx.encode_base64("einstein:password"), value)
        end)
        it("hides credential sent along with authorization header to upstream server", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              host          = "ldap2.com",
              authorization = "ldap " .. ngx.encode_base64("einstein:password")
            }
          })
          assert.response(res).has.status(200)
          assert.request(res).has.no.header("authorization")
        end)
        it("passes if custom credential type is given in post request", function()
          local r = assert(proxy_client:send {
            method = "POST",
            path = "/request",
            body = {},
            headers = {
              host = "ldap5.com",
              authorization = "basic " .. ngx.encode_base64("einstein:password"),
              ["content-type"] = "application/x-www-form-urlencoded",
            }
          })
          assert.response(r).has.status(200)
        end)
        it("injects conf.header_type in WWW-Authenticate header", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              host  = "ldap5.com",
            }
          })
          assert.response(res).has.status(401)

          local value = assert.response(res).has.header("www-authenticate")
          assert.equal('Basic realm="kong"', value)
          local json = assert.response(res).has.jsonbody()
          assert.equal("Unauthorized", json.message)
        end)
        it("fails if custom credential type is invalid in post request", function()
          local r = assert(proxy_client:send {
            method = "POST",
            path = "/request",
            body = {},
            headers = {
              host = "ldap5.com",
              authorization = "invalidldap " .. ngx.encode_base64("einstein:password"),
              ["content-type"] = "application/x-www-form-urlencoded",
            }
          })
          assert.response(r).has.status(401)
        end)
        it("passes if credential is valid in get request using global plugin", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              host          = "ldap6.com",
              authorization = "ldap " .. ngx.encode_base64("einstein:password")
            }
          })
          assert.response(res).has.status(200)
          local value = assert.request(res).has.header("x-credential-username")
          assert.are.equal("einstein", value)
          assert.request(res).has_not.header("x-anonymous-username")
        end)
        it("caches LDAP Auth Credential", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              host          = "ldap2.com",
              authorization = "ldap " .. ngx.encode_base64("einstein:password")
            }
          })
          assert.response(res).has.status(200)

          -- Check that cache is populated
          local key = cache_key(plugin2.config, "einstein", "password")

          helpers.wait_until(function()
            local res = assert(admin_client:send {
              method  = "GET",
              path    = "/cache/" .. key
            })
            res:read_body()
            return res.status == 200
          end)

          -- Check that cache is invalidated
          helpers.wait_for_invalidation(key, plugin2.config.cache_ttl + 10)
        end)

        describe("config.anonymous", function()
          it("works with right credentials and anonymous", function()
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = "/request",
              headers = {
                host          = "ldap3.com",
                authorization = "ldap " .. ngx.encode_base64("einstein:password")
              }
            })
            assert.response(res).has.status(200)

            local value = assert.request(res).has.header("x-credential-username")
            assert.are.equal("einstein", value)
            assert.request(res).has_not.header("x-anonymous-username")
          end)
          it("works with wrong credentials and anonymous", function()
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = "/request",
              headers = {
                host  = "ldap3.com"
              }
            })
            assert.response(res).has.status(200)
            local value = assert.request(res).has.header("x-anonymous-consumer")
            assert.are.equal("true", value)
            value = assert.request(res).has.header("x-consumer-username")
            assert.equal('no-body', value)
          end)
          it("works with wrong credentials and username in anonymous", function()
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = "/request",
              headers = {
                host  = "ldap7.com"
              }
            })
            assert.response(res).has.status(200)
            local value = assert.request(res).has.header("x-anonymous-consumer")
            assert.are.equal("true", value)
            value = assert.request(res).has.header("x-consumer-username")
            assert.equal('no-body', value)
          end)
          it("errors when anonymous user doesn't exist", function()
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = "/request",
              headers = {
                ["Host"] = "ldap4.com"
              }
            })
            assert.response(res).has.status(500)
          end)
        end)
      end)

      describe("Plugin: ldap-auth (access) [#" .. strategy .. "]", function()
        local proxy_client
        local user
        local anonymous

        lazy_setup(function()
          local bp = helpers.get_db_utils(strategy, {
            "routes",
            "services",
            "plugins",
            "consumers",
            "keyauth_credentials",
          })

          local service1 = bp.services:insert({
            path = "/request"
          })

          local route1 = bp.routes:insert {
            hosts   = { "logical-and.com" },
            service = service1,
          }

          bp.plugins:insert {
            route = { id = route1.id },
            name     = "ldap-auth",
            config   = {
              ldap_host = ldap_host_aws,
              ldap_port = 389,
              start_tls = ldap_strategy.start_tls,
              base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
              attribute = "uid",
            },
          }

          bp.plugins:insert {
            name     = "key-auth",
            route = { id = route1.id },
          }

          anonymous = bp.consumers:insert {
            username = "Anonymous",
          }

          user = bp.consumers:insert {
            username = "Mickey",
          }

          local service2 = bp.services:insert({
            path = "/request"
          })

          local route2 = bp.routes:insert {
            hosts   = { "logical-or.com" },
            service = service2
          }

          bp.plugins:insert {
            route = { id = route2.id },
            name     = "ldap-auth",
            config   = {
              ldap_host = ldap_host_aws,
              ldap_port = 389,
              start_tls = ldap_strategy.start_tls,
              base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
              attribute = "uid",
              anonymous = anonymous.id,
            },
          }

          bp.plugins:insert {
            name     = "key-auth",
            route = { id = route2.id },
            config   = {
              anonymous = anonymous.id,
            },
          }

          bp.keyauth_credentials:insert {
            key      = "Mouse",
            consumer = { id = user.id },
          }

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          }))

          proxy_client = helpers.proxy_client()
        end)


        lazy_teardown(function()
          if proxy_client then
            proxy_client:close()
          end

          helpers.stop_kong()
        end)

        describe("multiple auth without anonymous, logical AND", function()

          it("passes with all credentials provided", function()
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = "/request",
              headers = {
                ["Host"]          = "logical-and.com",
                ["apikey"]        = "Mouse",
                ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
              }
            })
            assert.response(res).has.status(200)
            assert.request(res).has.no.header("x-anonymous-consumer")
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
                ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
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
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = "/request",
              headers = {
                ["Host"]          = "logical-or.com",
                ["apikey"]        = "Mouse",
                ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
              }
            })
            assert.response(res).has.status(200)
            assert.request(res).has.no.header("x-anonymous-consumer")
            local id = assert.request(res).has.header("x-consumer-id")
            assert.not_equal(id, anonymous.id)
            assert(id == user.id)
          end)

          it("passes with only the first credential provided", function()
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = "/request",
              headers = {
                ["Host"]   = "logical-or.com",
                ["apikey"] = "Mouse",
              }
            })
            assert.response(res).has.status(200)
            assert.request(res).has.no.header("x-anonymous-consumer")
            local id = assert.request(res).has.header("x-consumer-id")
            assert.not_equal(id, anonymous.id)
            assert.equal(user.id, id)
          end)

          it("passes with only the second credential provided", function()
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = "/request",
              headers = {
                ["Host"]          = "logical-or.com",
                ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
              }
            })
            assert.response(res).has.status(200)
            assert.request(res).has.no.header("x-anonymous-consumer")
            local id = assert.request(res).has.header("x-credential-username")
            assert.equal("einstein", id)
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
    end
  end)
end
