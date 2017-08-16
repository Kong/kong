local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"

local function acl_cache_key(api_id, username)
  return "ldap_auth_cache:" .. api_id .. ":" .. username
end

local ldap_host_aws = "ec2-54-172-82-117.compute-1.amazonaws.com"

describe("Plugin: ldap-auth (access)", function()
  local client, client_admin, api2, plugin2
  setup(function()
    helpers.run_migrations()

    local api1 = assert(helpers.dao.apis:insert {
      name = "test-ldap",
      hosts = { "ldap.com" },
      upstream_url = "http://mockbin.com"
    })
    api2 = assert(helpers.dao.apis:insert {
      name = "test-ldap2",
      hosts = { "ldap2.com" },
      upstream_url = "http://mockbin.com"
    })
    local api3 = assert(helpers.dao.apis:insert {
      name = "test-ldap3",
      hosts = { "ldap3.com" },
      upstream_url = "http://mockbin.com"
    })
    local api4 = assert(helpers.dao.apis:insert {
      name = "test-ldap4",
      hosts = { "ldap4.com" },
      upstream_url = "http://mockbin.com"
    })

    local anonymous_user = assert(helpers.dao.consumers:insert {
      username = "no-body"
    })

    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "ldap-auth",
      config = {
        ldap_host = ldap_host_aws,
        ldap_port = "389",
        start_tls = false,
        base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com",
        attribute = "uid"
      }
    })

    plugin2 = assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "ldap-auth",
      config = {
        ldap_host = ldap_host_aws,
        ldap_port = "389",
        start_tls = false,
        base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com",
        attribute = "uid",
        hide_credentials = true,
        cache_ttl = 2,
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api3.id,
      name = "ldap-auth",
      config = {
        ldap_host = ldap_host_aws,
        ldap_port = "389",
        start_tls = false,
        base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com",
        attribute = "uid",
        anonymous = anonymous_user.id,
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api4.id,
      name = "ldap-auth",
      config = {
        ldap_host = "ec2-54-210-29-167.compute-1.amazonaws.com",
        ldap_port = "389",
        start_tls = false,
        base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com",
        attribute = "uid",
        cache_ttl = 2,
        anonymous = utils.uuid(), -- non existing consumer
      }
    })

    assert(helpers.start_kong())
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
    client_admin = helpers.admin_client()
  end)

  after_each(function()
    if client then client:close() end
  end)

  it("returns 'invalid credentials' and www-authenticate header when the credential is missing", function()
    local r = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "ldap.com"
      }
    })
    assert.response(r).has.status(401)
    local value = assert.response(r).has.header("www-authenticate")
    assert.are.equal('LDAP realm="kong"', value)
    local json = assert.response(r).has.jsonbody()
    assert.equal("Unauthorized", json.message)
  end)
  it("returns 'invalid credentials' when credential value is in wrong format in authorization header", function()
    local r = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "ldap.com",
        authorization = "abcd"
      }
    })
    assert.response(r).has.status(403)
    local json = assert.response(r).has.jsonbody()
    assert.equal("Invalid authentication credentials", json.message)
  end)
  it("returns 'invalid credentials' when credential value is in wrong format in proxy-authorization header", function()
    local r = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "ldap.com",
        ["proxy-authorization"] = "abcd"
      }
    })
    assert.response(r).has.status(403)
    local json = assert.response(r).has.jsonbody()
    assert.equal("Invalid authentication credentials", json.message)
  end)
  it("returns 'invalid credentials' when credential value is missing in authorization header", function()
    local r = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "ldap.com",
        authorization = "ldap "
      }
    })
    assert.response(r).has.status(403)
    local json = assert.response(r).has.jsonbody()
    assert.equal("Invalid authentication credentials", json.message)
  end)
  it("passes if credential is valid in post request", function()
    local r = assert(client:send {
      method = "POST",
      path = "/request",
      body = {},
      headers = {
        host = "ldap.com",
        authorization = "ldap " .. ngx.encode_base64("einstein:password"),
        ["content-type"] = "application/x-www-form-urlencoded",
      }
    })
    assert.response(r).has.status(200)
  end)
  it("passes if credential is valid and starts with space in post request", function()
    local r = assert(client:send {
      method = "POST",
      path = "/request",
      headers = {
        host = "ldap.com",
        authorization = " ldap " .. ngx.encode_base64("einstein:password")
      }
    })
    assert.response(r).has.status(200)
  end)
  it("passes if signature type indicator is in caps and credential is valid in post request", function()
    local r = assert(client:send {
      method = "POST",
      path = "/request",
      headers = {
        host = "ldap.com",
        authorization = "LDAP " .. ngx.encode_base64("einstein:password")
      }
    })
    assert.response(r).has.status(200)
  end)
  it("passes if credential is valid in get request", function()
    local r = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "ldap.com",
        authorization = "ldap " .. ngx.encode_base64("einstein:password")
      }
    })
    assert.response(r).has.status(200)
    local value = assert.request(r).has.header("x-credential-username")
    assert.are.equal("einstein", value)
    assert.request(r).has_not.header("x-anonymous-username")
  end)
  it("authorization fails if credential does has no password encoded in get request", function()
    local r = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "ldap.com",
        authorization = "ldap " .. ngx.encode_base64("einstein:")
      }
    })
    assert.response(r).has.status(403)
  end)
  it("authorization fails if credential has multiple encoded usernames or passwords separated by ':' in get request", function()
    local r = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "ldap.com",
        authorization = "ldap " .. ngx.encode_base64("einstein:password:another_password")
      }
    })
    assert.response(r).has.status(403)
  end)
  it("does not pass if credential is invalid in get request", function()
    local r = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "ldap.com",
        authorization = "ldap " .. ngx.encode_base64("einstein:wrong_password")
      }
    })
    assert.response(r).has.status(403)
  end)
  it("does not hide credential sent along with authorization header to upstream server", function()
    local r = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "ldap.com",
        authorization = "ldap " .. ngx.encode_base64("einstein:password")
      }
    })
    assert.response(r).has.status(200)
    local value = assert.request(r).has.header("authorization")
    assert.equal("ldap " .. ngx.encode_base64("einstein:password"), value)
  end)
  it("hides credential sent along with authorization header to upstream server", function()
    local r = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "ldap2.com",
        authorization = "ldap " .. ngx.encode_base64("einstein:password")
      }
    })
    assert.response(r).has.status(200)
    assert.request(r).has.no.header("authorization")
  end)
  it("caches LDAP Auth Credential", function()
    local r = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "ldap2.com",
        authorization = "ldap " .. ngx.encode_base64("einstein:password")
      }
    })
    assert.response(r).has.status(200)

    -- Check that cache is populated
    local cache_key = acl_cache_key(api2.id, "einstein")

    helpers.wait_until(function()
      local res = assert(client_admin:send {
        method = "GET",
        path = "/cache/" .. cache_key
      })
      res:read_body()
      return res.status == 200
    end)

    -- Check that cache is invalidated
    helpers.wait_until(function()
      local res = client_admin:send {
        method = "GET",
        path = "/cache/" .. cache_key
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
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "ldap3.com",
          authorization = "ldap " .. ngx.encode_base64("einstein:password")
        }
      })
      assert.response(r).has.status(200)

      local value = assert.request(r).has.header("x-credential-username")
      assert.are.equal("einstein", value)
      assert.request(r).has_not.header("x-anonymous-username")
    end)
    it("works with wrong credentials and anonymous", function()
       local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "ldap3.com"
        }
      })
      assert.response(r).has.status(200)
      local value = assert.request(r).has.header("x-anonymous-consumer")
      assert.are.equal("true", value)
      value = assert.request(r).has.header("x-consumer-username")
      assert.equal('no-body', value)
    end)
    it("errors when anonymous user doesn't exist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "ldap4.com"
        }
      })
      assert.response(res).has.status(500)
    end)
  end)
end)



describe("Plugin: ldap-auth (access)", function()

  local client, user1, anonymous

  setup(function()
    local api1 = assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "logical-and.com" },
      upstream_url = "http://mockbin.org/request"
    })
    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "ldap-auth",
      config = {
        ldap_host = ldap_host_aws,
        ldap_port = "389",
        start_tls = false,
        base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com",
        attribute = "uid",
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api1.id
    })

    anonymous = assert(helpers.dao.consumers:insert {
      username = "Anonymous"
    })
    user1 = assert(helpers.dao.consumers:insert {
      username = "Mickey"
    })

    local api2 = assert(helpers.dao.apis:insert {
      name = "api-2",
      hosts = { "logical-or.com" },
      upstream_url = "http://mockbin.org/request"
    })
    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "ldap-auth",
      config = {
        ldap_host = ldap_host_aws,
        ldap_port = "389",
        start_tls = false,
        base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com",
        attribute = "uid",
        anonymous = anonymous.id,
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api2.id,
      config = {
        anonymous = anonymous.id
      }
    })

    assert(helpers.dao.keyauth_credentials:insert {
      key = "Mouse",
      consumer_id = user1.id
    })

    assert(helpers.start_kong())
    client = helpers.proxy_client()
  end)


  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("multiple auth without anonymous, logical AND", function()

    it("passes with all credentials provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
          ["apikey"] = "Mouse",
          ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
    end)

    it("fails 401, with only the first credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
          ["apikey"] = "Mouse",
        }
      })
      assert.response(res).has.status(401)
    end)

    it("fails 401, with only the second credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
          ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
        }
      })
      assert.response(res).has.status(401)
    end)

    it("fails 401, with no credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
        }
      })
      assert.response(res).has.status(401)
    end)

  end)

  describe("multiple auth with anonymous, logical OR", function()

    it("passes with all credentials provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
          ["apikey"] = "Mouse",
          ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert(id == user1.id)
    end)

    it("passes with only the first credential provided", function()
      local res = assert(client:send {
        method = "GET",
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
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
          ["Authorization"] = "ldap " .. ngx.encode_base64("einstein:password"),
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-credential-username")
      assert.equal("einstein", id)
    end)

    it("passes with no credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
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
