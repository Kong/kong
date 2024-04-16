-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http_mock = require "spec.helpers.http_mock"
local oauth_client = require "spec.helpers.oauth_client"
local jwt = require "kong.openid-connect.jwt"
local json = require "cjson"

local jwks = require "spec.fixtures.jwks"
local client_jwk = jwks.client_jwk
local client_jwk_public = jwks.client_jwk_public

local function enable_dpop(client)
  client.client_jwk = client_jwk
  client.client_jwk_public = client_jwk_public
  client.using_dpop = true
end

local function user_password(client)
  client.username = "testtest"
  client.password = "test"
end


pending("OAuth Client", function()
  local rp
  local client
  -- TODO: start a IdP for the test
  -- all the tests pass on my local environment

  lazy_setup(function ()
    rp = http_mock.new(9876, nil, {
      log_opts = {
        req = true,
        req_body = true,
        req_large_body = true,
      }
    })
    assert(rp:start())
  end)

  lazy_teardown(function ()
    rp:stop()
  end)

  before_each(function ()
    client = oauth_client.new({
      issuer = "http://localhost:8080/realms/master",
      client_uri = "http://localhost:9876",
      client_id = "test",
      client_secret = "AXxLRK1zqEnvwV37fbYCd0VJBdCAVlw9",
      -- dump_req = true,
    })

    enable_dpop(client)
  end)

  it("get config", function()
    local idp_config = client.idp_config
    assert.same("http://localhost:8080/realms/master", idp_config.issuer)
    assert.same("http://localhost:8080/realms/master/protocol/openid-connect/auth", idp_config.authorization_endpoint)
    assert.same("http://localhost:8080/realms/master/protocol/openid-connect/token", idp_config.token_endpoint)
    assert.same("http://localhost:8080/realms/master/protocol/openid-connect/userinfo", idp_config.userinfo_endpoint)
  end)

  it("token endpoint&refresh", function()
    local param = {
      grant_type = "password",
      scope = { "openid" },
    }

    user_password(param)

    local token = client:get_token(param)

    local old_token = token.access_token
    assert.is_truthy(old_token)

    local refresh_token = client:refresh_token()
    assert.is_truthy(refresh_token.access_token)
    assert.not_same(old_token, refresh_token.access_token)
  end)

  it("generate dpop proof", function()
    enable_dpop(client)
    local proof = client:generate_dpop_proof({
      method = "GET",
      url = "https://example.com",
    }, {
      nonce = "123",
    })

    local decoded = jwt:decode(proof)
    assert.same("GET", decoded.payload.htm)
    assert.same("https://example.com", decoded.payload.htu)
    assert.same("123", decoded.payload.nonce)
  end)

  it("DPoP working&refreshing", function()
    enable_dpop(client)
    user_password(client)
    local tokens = client:login()
    assert.same("DPoP", tokens.token_type)

    local old_token = tokens.access_token
    assert.truthy(old_token)

    local refresh_token = client:refresh_token()
    assert.truthy(refresh_token.access_token)
    assert.not_same(old_token, refresh_token.access_token)
  end)

  it("DPoP RP request", function()
    client.auto_login = true
    enable_dpop(client)
    user_password(client)
    local res = assert(client:rp_request("/test"))
    assert.same(200, res.status)

    local req = rp:get_request()

    assert.same("GET", req.method)
    assert.same("/test", req.uri)
    local auth = req.headers["Authorization"]
    assert.truthy(auth, "Authorization header is missing")
    local access_token = auth:match("DPoP%s+(.+)") or auth:match("Bearer%s+(.+)")
    assert.truthy(access_token, "JWT is missing")
    
    local header, payload, _ = access_token:match("([^.]+)%.([^.]+)%.([^.]+)")
    header = json.decode(ngx.decode_base64(header))
    payload = json.decode(ngx.decode_base64(payload))

    assert.truthy(payload.cnf)
    assert.truthy(payload.cnf.jkt)
    
    local dpop = req.headers["DPoP"]
    assert.truthy(dpop, "DPoP header is missing")
    local proof = jwt:decode(dpop)
    local payload = proof.payload
    assert.same("GET", payload.htm)
    assert.same("http://localhost:9876/test", payload.htu)
  end)
end)
