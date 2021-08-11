-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers = require "spec.helpers"


local PLUGIN_NAME = "openid-connect"
local KEYCLOAK_HOST = "keycloak"
local KEYCLOAK_PORT = 8080
local KEYCLOAK_SSL_PORT = 8443
local REALM_PATH = "/auth/realms/demo"
local DISCOVERY_PATH = "/.well-known/openid-configuration"



describe(PLUGIN_NAME .. ": (keycloak)", function()
  it("can access openid connect discovery endpoint on demo realm with http", function()
    local client = helpers.http_client(KEYCLOAK_HOST, KEYCLOAK_PORT)
    local res = client:get(REALM_PATH .. DISCOVERY_PATH)
    assert.response(res).has.status(200)
    local json = assert.response(res).has.jsonbody()
    assert.equal("http://" .. KEYCLOAK_HOST .. ":" .. KEYCLOAK_PORT .. REALM_PATH, json.issuer)
  end)

  it("can access openid connect discovery endpoint on demo realm with https", function()
    local client = helpers.http_client(KEYCLOAK_HOST, KEYCLOAK_SSL_PORT)
    assert(client:ssl_handshake(nil, KEYCLOAK_HOST, false))
    local res = client:get(REALM_PATH .. DISCOVERY_PATH)
    assert.response(res).has.status(200)
    local json = assert.response(res).has.jsonbody()
    assert.equal("https://" .. KEYCLOAK_HOST .. ":" .. KEYCLOAK_SSL_PORT .. REALM_PATH, json.issuer)
  end)
end)
