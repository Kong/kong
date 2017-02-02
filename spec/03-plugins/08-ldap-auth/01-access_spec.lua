local cache = require "kong.tools.database_cache"
local helpers = require "spec.helpers"

describe("Plugin: ldap-auth (access)", function()
  local client, client_admin, api2, plugin2
  local ldap_host_aws = "ec2-54-172-82-117.compute-1.amazonaws.com"
  setup(function()
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
        anonymous = true
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
        authorization = "ldap "..ngx.encode_base64("einstein:password"),
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
        authorization = " ldap "..ngx.encode_base64("einstein:password")
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
        authorization = "LDAP "..ngx.encode_base64("einstein:password")
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
        authorization = "ldap "..ngx.encode_base64("einstein:password")
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
        authorization = "ldap "..ngx.encode_base64("einstein:")
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
        authorization = "ldap "..ngx.encode_base64("einstein:password:another_password")
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
        authorization = "ldap "..ngx.encode_base64("einstein:wrong_password")
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
        authorization = "ldap "..ngx.encode_base64("einstein:password")
      }
    })
    assert.response(r).has.status(200)
    local value = assert.request(r).has.header("authorization")
    assert.equal("ldap "..ngx.encode_base64("einstein:password"), value)
  end)
  it("hides credential sent along with authorization header to upstream server", function()
    local r = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "ldap2.com",
        authorization = "ldap "..ngx.encode_base64("einstein:password")
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
        authorization = "ldap "..ngx.encode_base64("einstein:password")
      }
    })
    assert.response(r).has.status(200)

    -- Check that cache is populated
    local cache_key = cache.ldap_credential_key(api2.id , "einstein")
    helpers.wait_until(function()
      local res = assert(client_admin:send {
        method = "GET",
        path = "/cache/"..cache_key
      })
      res:read_body()
      return res.status == 200
    end)

    -- Check that cache is invalidated
    helpers.wait_until(function()
      local res = client_admin:send {
        method = "GET",
        path = "/cache/"..cache_key
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
          authorization = "ldap "..ngx.encode_base64("einstein:password")
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
      assert.request(r).has_not.header("x-consumer-username")
    end)
  end)
end)
