local helpers = require "spec.helpers"
local base64 = require "base64"
local cache = require "kong.tools.database_cache"

describe("Plugin: ldap-auth (access)", function()
  local client
  setup(function()
    local api1 = assert(helpers.dao.apis:insert {
      name = "test-ldap",
      request_host = "ldap.com",
      upstream_url = "http://mockbin.com"
    })
    local api2 = assert(helpers.dao.apis:insert {
      name = "test-ldap2",
      request_host = "ldap2.com",
      upstream_url = "http://mockbin.com"
    })

    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "ldap-auth",
      config = {
        ldap_host = "ec2-54-210-29-167.compute-1.amazonaws.com",
        ldap_port = "389",
        start_tls = false,
        base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com",
        attribute = "uid"
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "ldap-auth",
      config = {
        ldap_host = "ec2-54-210-29-167.compute-1.amazonaws.com",
        ldap_port = "389",
        start_tls = false,
        base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com",
        attribute = "uid",
        hide_credentials = true
      }
    })

    helpers.prepare_prefix()
    assert(helpers.start_kong())
  end)
  teardown(function()
    assert(helpers.stop_kong())
  end)

  before_each(function()
    client = helpers.proxy_client()
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
        authorization = "ldap "..base64.encode("einstein:password"),
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
        authorization = " ldap "..base64.encode("einstein:password")
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
        authorization = "LDAP "..base64.encode("einstein:password")
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
        authorization = "ldap "..base64.encode("einstein:password")
      }
    })
    assert.response(r).has.status(200)
    local value = assert.request(r).has.header("x-credential-username")
    assert.are.equal("einstein", value)
  end)
  it("authorization fails if credential does has no password encoded in get request", function()
    local r = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "ldap.com",
        authorization = "ldap "..base64.encode("einstein:")
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
        authorization = "ldap "..base64.encode("einstein:password:another_password")
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
        authorization = "ldap "..base64.encode("einstein:wrong_password")
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
        authorization = "ldap "..base64.encode("einstein:password")
      }
    })
    assert.response(r).has.status(200)
    local value = assert.request(r).has.header("authorization")
    assert.equal("ldap "..base64.encode("einstein:password"), value)
  end)
  it("hides credential sent along with authorization header to upstream server", function()
    local r = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "ldap2.com",
        authorization = "ldap "..base64.encode("einstein:password")
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
        host = "ldap.com",
        authorization = "ldap "..base64.encode("einstein:password")
      }
    })
    assert.response(r).has.status(200)

    -- Check that cache is populated
    local cache_key = cache.ldap_credential_key("einstein")
    local exists = true
    while(exists) do
      local r = assert(client:send {
        method = "GET",
        path = "/cache/"..cache_key,
      })
      if r.status ~= 200 then
        exists = false
      end
    end
    assert.equals(200, r.status)
  end)
end)
