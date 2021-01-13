-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local x509 = require "resty.openssl.x509"
local pkey = require "resty.openssl.pkey"
local name = require "resty.openssl.x509.name"

_G.kong = {
  configuration = {
    cluster_mtls = "pki_check_cn",
  },
}

local function create_self_signed(cn)
  local key = pkey.new({
    type = 'EC',
  })

  local cert = x509.new()
  cert:set_pubkey(key)
  cert:set_version(3)

  local now = os.time()
  cert:set_not_before(now)
  cert:set_not_after(now + 86400)

  local nm = name.new()
  assert(nm:add("CN", cn))

  assert(cert:set_subject_name(nm))
  assert(cert:set_issuer_name(nm))

  assert(cert:sign(key))

  return cert:to_PEM(), key:to_PEM("private")
end

describe("hybrid mode validate client cert", function()
  local clustering = require "kong.clustering"

  clustering.init({
    role = "control_plane",
    -- CN is server.kong_clustering_pki.domain
    cluster_cert = "spec/fixtures/kong_clustering_server.crt",
    cluster_cert_key = "spec/fixtures/kong_clustering_server.key",
  })

  it("validates if client cert in the same domain of server", function()
    local cert = create_self_signed("somedp.kong_clustering_pki.domain")
    local ok, _ = clustering._validate_client_cert(cert)
    assert.is_true(ok)
  end)

  it("rejects if client cert is in different domain of server", function()
    local cert = create_self_signed("somedp.not_kong_clustering_pki.domain")
    local ok, err = clustering._validate_client_cert(cert)
    assert.is_falsy(ok)
    assert.matches("expected CN as subdomain of", err)
  end)
end)

describe("hybrid mode validate client cert", function()

  local clustering = require "kong.clustering"

  lazy_setup(function()
    local cert, key = create_self_signed("random.domain")
    local f = assert(io.open("/tmp/pki_random.crt", "w"))
    f:write(cert)
    f:close()
    f = assert(io.open("/tmp/pki_random.key", "w"))
    f:write(key)
    f:close()

    clustering.init({
      role = "control_plane",
      cluster_mtls = "pki_check_cn",
      -- CN is server.kong_clustering_pki.domain
      cluster_cert = "/tmp/pki_random.crt",
      cluster_cert_key = "/tmp/pki_random.key",
    })
  end)

  lazy_teardown(function()
    os.remove("/tmp/pki_random.crt")
    os.remove("/tmp/pki_random.key")
  end)

  it("rejects if client cert is a top level domain", function()
    local cert = create_self_signed("another.domain")
    local ok, _ = clustering._validate_client_cert(cert)
    assert.is_truthy(ok)
  end)
end)
