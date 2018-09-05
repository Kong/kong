local ca_tools = require "kong.tools.ca"
local openssl_pkey = require "openssl.pkey"

describe("kong.tools.ca", function()
  it(".new_key generates a private key", function()
    local key = ca_tools.new_key()
    assert.same("userdata", type(key))
    assert.same("string", type(key:toPEM()))
  end)

  it(".new_ca generates a suitable CA", function()
    local ca_key = ca_tools.new_key()
    local ca_cert = ca_tools.new_ca(ca_key)
    assert.same("userdata", type(ca_cert))
    assert.same("string", type(ca_cert:toPEM()))
    -- Has the correct key
    assert.same(ca_key:toPEM("public"), ca_cert:getPublicKey():toPEM("public"))
    -- Has CA flag set
    assert.same(true, ca_cert:getBasicConstraints("CA"))
    assert.same(true, ca_cert:getBasicConstraintsCritical())
    -- Is self-signed
    assert.same(true, ca_cert:isIssuedBy(ca_cert))
  end)

  it(".new_node_cert creates a signed cert", function()
    local ca_key = ca_tools.new_key()
    local ca_cert = ca_tools.new_ca(ca_key)
    local node_key = ca_tools.new_key()
    local node_public_key = openssl_pkey.new(node_key:toPEM("public"))
    local node_cert = ca_tools.new_node_cert(ca_key, ca_cert, {
      node_pub_key = node_public_key,
      node_id = "test",
    })
    assert.same("userdata", type(node_cert))
    assert.same("string", type(node_cert:toPEM()))
    -- Has the correct key
    assert.same(node_key:toPEM("public"), node_cert:getPublicKey():toPEM("public"))
    -- Has CA flag *not* set
    assert.same(false, node_cert:getBasicConstraints("CA"))
    assert.same(true, node_cert:getBasicConstraintsCritical())
    -- Is signed by CA
    assert.same(true, node_cert:isIssuedBy(ca_cert))
  end)
end)
