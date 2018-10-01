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


for _, strategy in helpers.each_strategy() do
  describe("Plugin: ldap-auth-advanced (access) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client
    local route2
    local plugin2

    setup(function()
      local bp = helpers.get_db_utils(strategy)

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
        hosts   = { "ldap7.com" },
      }

      local route8 = bp.routes:insert {
        hosts   = { "ldap8.com" },
      }

      local anonymous_user = bp.consumers:insert {
        username = "no-body"
      }

      bp.plugins:insert {
        route_id = route1.id,
        name     = "ldap-auth-advanced",
        config   = {
          consumer_optional = true,
          ldap_host = ldap_host_aws,
          ldap_port = "389",
          start_tls = false,
          base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute = "uid"
        }
      }

      plugin2 = bp.plugins:insert {
        route_id = route2.id,
        name     = "ldap-auth-advanced",
        config   = {
          consumer_optional     = true,
          ldap_host        = ldap_host_aws,
          ldap_port        = "389",
          start_tls        = false,
          base_dn          = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute        = "uid",
          hide_credentials = true,
          cache_ttl        = 2,
        }
      }

      bp.plugins:insert {
        route_id = route3.id,
        name     = "ldap-auth-advanced",
        config   = {
          consumer_optional = true,
          ldap_host = ldap_host_aws,
          ldap_port = "389",
          start_tls = false,
          base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute = "uid",
          anonymous = anonymous_user.id,
        }
      }

      bp.plugins:insert {
        route_id = route4.id,
        name     = "ldap-auth-advanced",
        config   = {
          consumer_optional = true,
          ldap_host = "ec2-54-210-29-167.compute-1.amazonaws.com",
          ldap_port = "389",
          start_tls = false,
          base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute = "uid",
          cache_ttl = 2,
          anonymous = utils.uuid(), -- non existing consumer
        }
      }

      bp.plugins:insert {
        route_id = route5.id,
        name     = "ldap-auth-advanced",
        config   = {
          consumer_optional = true,
          ldap_host = ldap_host_aws,
          ldap_port = "389",
          start_tls = false,
          base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute = "uid",
          header_type = "basic",
        }
      }

      bp.plugins:insert {
        name     = "ldap-auth-advanced",
        config   = {
          consumer_optional = true,
          ldap_host = ldap_host_aws,
          ldap_port = "389",
          start_tls = false,
          base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute = "uid"
        }
      }

      bp.plugins:insert {
        route_id = route7.id,
        name     = "ldap-auth-advanced",
        config   = {
          consumer_optional = true,
          ldap_host         = ldap_host_aws,
          ldap_password     = "password",
          ldap_port         = "389",
          start_tls         = false,
          bind_dn           = "uid=einstein,ou=scientists,dc=ldap,dc=mashape,dc=com",
          base_dn           = "dc=ldap,dc=mashape,dc=com",
          attribute         = "uid",
          hide_credentials  = true,
          cache_ttl         = 2,
        }
      }

      bp.plugins:insert {
        route_id = route8.id,
        name     = "ldap-auth-advanced",
        config   = {
          consumer_optional = true,
          ldap_host         = ldap_host_aws,
          ldap_password     = "password",
          ldap_port         = "389",
          start_tls         = false,
          bind_dn           = "uid=einstein,ou=scientists,dc=ldap,dc=mashape,dc=com",
          base_dn           = "dc=ldap,dc=mashape,dc=com",
          attribute         = "cn",
          hide_credentials  = true,
          cache_ttl         = 2,
        }
      }

      assert(helpers.start_kong({
        custom_plugins = "ldap-auth-advanced",
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
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

    it("passes if credential is valid request with bind_dn", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/get",
        body    = {},
        headers = {
          host             = "ldap7.com",
          authorization    = "ldap " .. ngx.encode_base64("euclid:password"),
        }
      })
      assert.response(res).has.status(200)
    end)

    it("passes if credential contains non-word characters", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/get",
        body    = {},
        headers = {
          host             = "ldap7.com",
          authorization    = "ldap " .. ngx.encode_base64("john.nash:password"),
        }
      })
      assert.response(res).has.status(200)
    end)

    it("returns forbidden if user cannot be found with valid bind_dn", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/get",
        body    = {},
        headers = {
          host             = "ldap7.com",
          authorization    = "ldap " .. ngx.encode_base64("nobody:found"),
        }
      })
      assert.response(res).has.status(403)
      local json = assert.response(res).has.jsonbody()
      assert.equal("Invalid authentication credentials", json.message)
    end)

    it("passes if attribute is cn instead of uid with bind_dn", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/get",
        body    = {},
        headers = {
          host             = "ldap8.com",
          authorization    = "ldap " .. ngx.encode_base64("einstein:password"),
        }
      })

      assert.response(res).has.status(200)
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
      assert.response(res).has.status(403)
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
      assert.response(res).has.status(403)
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
      assert.response(res).has.status(403)
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
      assert.response(r).has.status(403)
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
      assert.response(res).has.status(403)
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
			assert.response(res).has.status(403)
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
      assert.response(res).has.status(403)
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
      assert.response(res).has.status(403)
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
      assert.response(r).has.status(403)
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
      helpers.wait_until(function()
        local res = admin_client:send {
          method  = "GET",
          path    = "/cache/" .. key
        }
        res:read_body()
        --if res.status ~= 404 then
        --  ngx.sleep( plugin2.config.cache_ttl / 5 )
        --end
        return res.status == 404
      end, plugin2.config.cache_ttl + 10)
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
      it("fails 500 when anonymous user doesn't exist", function()
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

  describe("Plugin: ldap-auth-advanced (access) [#" .. strategy .. "]", function()
    local proxy_client
    local user
    local anonymous

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local service1 = bp.services:insert({
        path = "/request"
      })

      local route1 = bp.routes:insert {
        hosts   = { "logical-and.com" },
        service = service1,
      }

      bp.plugins:insert {
        route_id = route1.id,
        name     = "ldap-auth-advanced",
        config   = {
          consumer_optional = true,
          ldap_host = ldap_host_aws,
          ldap_port = "389",
          start_tls = false,
          base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute = "uid",
        },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route_id = route1.id,
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
        route_id = route2.id,
        name     = "ldap-auth-advanced",
        config   = {
          consumer_optional = true,
          ldap_host = ldap_host_aws,
          ldap_port = "389",
          start_tls = false,
          base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute = "uid",
          anonymous = anonymous.id,
        },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route_id = route2.id,
        config   = {
          anonymous = anonymous.id,
        },
      }

      bp.keyauth_credentials:insert {
        key         = "Mouse",
        consumer_id = user.id,
      }

      assert(helpers.start_kong({
        custom_plugins = "ldap-auth-advanced",
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)


    teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong(nil, true)
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

  describe("Plugin: ldap-auth-advanced (access) [#" .. strategy .. "]", function()
    local proxy_client, admin_client
    local bp
    local dao
    local routes
    local plugin

    local consumer_with_custom_id, consumer2_with_custom_id
    local consumer_with_username, consumer2_with_username
    local anonymous_consumer

    setup(function()
      local _
      bp, _, dao = helpers.get_db_utils(strategy)

      routes = {
        bp.routes:insert {
          hosts = { "ldap.id.custom_id.username.com" },
        },

        bp.routes:insert {
          hosts = { "ldap.username.com" },
        },

        bp.routes:insert {
          hosts = { "ldap.custom_id.com" },
        },

        bp.routes:insert {
          hosts = { "ldap.anonymous.com" },
        },

        bp.routes:insert {
          hosts = { "ldap5.com" },
        },

        bp.routes:insert {
          hosts = { "ldap6.com" },
        },

        bp.routes:insert {
          hosts = { "ldap7.com" },
        },
      }

      consumer_with_username = bp.consumers:insert {
        username = "einstein"
      }

      consumer_with_custom_id = bp.consumers:insert {
        custom_id = "einstein"
      }

      consumer2_with_username = bp.consumers:insert {
        username = "euclid"
      }

      consumer2_with_custom_id = bp.consumers:insert {
        custom_id = "euclid"
      }

      anonymous_consumer = bp.consumers:insert {
        username = "whoknows"
      }

      bp.plugins:insert {
        route_id = routes[1].id,
        name     = "ldap-auth-advanced",
        config   = {
          ldap_host = ldap_host_aws,
          ldap_port = "389",
          start_tls = false,
          base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute = "uid"
        }
      }

      bp.plugins:insert {
        route_id = routes[2].id,
        name     = "ldap-auth-advanced",
        config   = {
          ldap_host = ldap_host_aws,
          ldap_port = "389",
          start_tls = false,
          consumer_by = { "username" },
          base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute = "uid",
        }
      }

      plugin = bp.plugins:insert {
        route_id = routes[3].id,
        name     = "ldap-auth-advanced",
        config   = {
          ldap_host = ldap_host_aws,
          ldap_port = "389",
          start_tls = false,
          consumer_by = { "custom_id" },
          base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute = "uid",
          cache_ttl = 2,
        }
      }

      bp.plugins:insert {
        route_id = routes[4].id,
        name     = "ldap-auth-advanced",
        config   = {
          ldap_host = ldap_host_aws,
          ldap_port = "389",
          start_tls = false,
          base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute = "uid",
          anonymous = anonymous_consumer.id
        }
      }

      bp.plugins:insert {
        route_id = routes[5].id,
        name     = "ldap-auth-advanced",
        config   = {
          ldap_host         = ldap_host_aws,
          ldap_password     = "password",
          ldap_port         = "389",
          start_tls         = false,
          bind_dn           = "uid=einstein,ou=scientists,dc=ldap,dc=mashape,dc=com",
          base_dn           = "dc=ldap,dc=mashape,dc=com",
          consumer_by       = { "custom_id" },
          attribute         = "uid",
          hide_credentials  = true,
          cache_ttl         = 2,
        }
      }

      bp.plugins:insert {
        route_id = routes[6].id,
        name     = "ldap-auth-advanced",
        config   = {
          ldap_host         = ldap_host_aws,
          ldap_password     = "password",
          ldap_port         = "389",
          start_tls         = false,
          bind_dn           = "uid=einstein,ou=scientists,dc=ldap,dc=mashape,dc=com",
          base_dn           = "dc=ldap,dc=mashape,dc=com",
          consumer_by       = { "username" },
          attribute         = "uid",
          hide_credentials  = true,
          cache_ttl         = 2,
        }
      }

      bp.plugins:insert {
        route_id = routes[7].id,
        name     = "ldap-auth-advanced",
        config   = {
          ldap_host         = ldap_host_aws,
          ldap_password     = "password",
          ldap_port         = "389",
          start_tls         = false,
          bind_dn           = "something=is,wrong=com",
          base_dn           = "dc=ldap,dc=mashape,dc=com",
          consumer_by       = { "username" },
          attribute         = "uid",
          hide_credentials  = true,
          cache_ttl         = 2,
        }
      }

      assert(helpers.start_kong({
        custom_plugins = "ldap-auth-advanced",
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
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

    describe("consumer mapping", function()

      it("passes auth and maps consumer with username only, consumer_by = username, custom_id", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]          = "ldap.id.custom_id.username.com",
            ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
          }
        })

        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        assert.are.equal('einstein',
                         assert.request(res).has.header("x-consumer-username"))
        assert.request(res).has.no.header("x-anonymous-consumer")
      end)

      it("passes auth and maps consumer with username only, consumer_by = username", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]          = routes[2].hosts[1],
            ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
          }
        })

        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        assert.are.equal(consumer_with_username.id,
                         assert.request(res).has.header("x-consumer-id"))
        assert.are.equal(consumer_with_username.username,
                         assert.request(res).has.header("x-consumer-username"))
      end)

      it("passes auth and maps consumer with custom_id only, consumer_by = custom_id", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]          = routes[3].hosts[1],
            ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
          }
        })

        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        assert.are.equal(consumer_with_custom_id.id,
                         assert.request(res).has.header("x-consumer-id"))
        assert.are.equal(consumer_with_custom_id.username,
                         assert.request(res).has.header("x-consumer-username"))
      end)

      it("fails ldap auth but maps to anonymous", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]          = routes[4].hosts[1],
            ["Authorization"] = "ldap " .. ngx.encode_base64("noway:jose"),
          }
        })

        assert.response(res).has.status(200)
        assert.are.equal(anonymous_consumer.id,
                         assert.request(res).has.header("x-consumer-id"))
        assert.are.equal(anonymous_consumer.username,
                         assert.request(res).has.header("x-consumer-username"))
        assert.are.equal("true",
                         assert.request(res).has.header("x-anonymous-consumer"))
      end)

      it("binds to anonymous with no credentials", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]          = routes[4].hosts[1]
          }
        })

        assert.response(res).has.status(200)
        assert.are.equal(anonymous_consumer.id,
                         assert.request(res).has.header("x-consumer-id"))
        assert.are.equal(anonymous_consumer.username,
                         assert.request(res).has.header("x-consumer-username"))
        assert.are.equal("true",
                         assert.request(res).has.header("x-anonymous-consumer"))
      end)

      it("caches LDAP consumer map by consumer_by and invalidates", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]          = routes[3].hosts[1],
            ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
          }
        })
        assert.response(res).has.status(200)
        assert.are.equal(consumer_with_custom_id.username,
                         assert.request(res).has.header("x-consumer-username"))
        --consumers:username:einstein:consumers:::
        local key = dao.consumers:cache_key("custom_id", consumer_with_custom_id.custom_id, "consumers")

        helpers.wait_until(function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/cache/" .. key
          })
          res:read_body()
          return res.status == 200
        end)

        admin_client:send {
          method = "DELETE",
          path = "/consumers/" .. consumer_with_custom_id.id
        }

        -- Check that cache is invalidated
        helpers.wait_until(function()
          local res = admin_client:send {
            method  = "GET",
            path    = "/cache/" .. key
          }
          res:read_body()
          return res.status == 404
        end, plugin.config.cache_ttl + 10)
      end)

      it("bind_dn passes and authenticates user and maps consumer with " ..
         "custom_id only, consumer_by = custom_id", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]          = routes[5].hosts[1],
            ["Authorization"] = "ldap " .. ngx.encode_base64("euclid:password"),
          }
        })

        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        assert.are.equal(consumer2_with_custom_id.id,
                         assert.request(res).has.header("x-consumer-id"))
        assert.are.equal(consumer2_with_custom_id.username,
                         assert.request(res).has.header("x-consumer-username"))
      end)

      it("bind_dn passes and authenticates user and maps consumer with " ..
         "username only, consumer_by = username", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]          = routes[6].hosts[1],
            ["Authorization"] = "ldap " .. ngx.encode_base64("euclid:password"),
          }
        })

        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        assert.are.equal(consumer2_with_username.id,
                         assert.request(res).has.header("x-consumer-id"))
        assert.are.equal(consumer2_with_username.username,
                         assert.request(res).has.header("x-consumer-username"))
      end)
      
      it("returns internal server error when bind_dn is invalid", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            ["Host"]          = routes[7].hosts[1],
            ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
          }
        })

        assert.response(res).has.status(500)
      end)
    end)
  end)
end
