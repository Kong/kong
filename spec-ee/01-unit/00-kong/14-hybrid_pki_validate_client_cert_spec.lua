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
  configuration = {},
}


local get_phase = ngx.get_phase
local mock_get_phase = function() return "init" end
local clustering = require "kong.clustering"

local function create_self_signed(cn)
  local key = pkey.new({
    type = 'EC',
    curve = 'prime256v1',
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
  ngx.get_phase = mock_get_phase -- luacheck: ignore
  local kong_clustering = clustering.new({
    role = "control_plane",
    -- CN is server.kong_clustering_pki.domain
    cluster_cert = "spec/fixtures/kong_clustering_server.crt",
    cluster_cert_key = "spec/fixtures/kong_clustering_server.key",
    -- the OCSP validation code path uses some OpenResty APIs that will
    -- throw an exception if used outside of a request context, so we
    -- need to explicitly disable it
    cluster_ocsp = "off",
    cluster_mtls = "pki_check_cn",
  })
  ngx.get_phase = get_phase -- luacheck: ignore

  it("validates if client cert in the same domain of server", function()
    local cert = create_self_signed("somedp.kong_clustering_pki.domain")
    local x509, err = kong_clustering:validate_client_cert(cert)
    assert.not_nil(x509)
    assert.is_nil(err)
  end)

  it("rejects if client cert is in different domain of server", function()
    local cert = create_self_signed("somedp.not_kong_clustering_pki.domain")
    local ok, err = kong_clustering:validate_client_cert(cert)
    assert.is_falsy(ok)
    assert.matches("data plane presented client certificate with incorrect CN", err)
  end)
end)

describe("hybrid mode validate client cert", function()

  local kong_clustering

  lazy_setup(function()
    local cert, key = create_self_signed("random.domain")
    local f = assert(io.open("/tmp/pki_random.crt", "w"))
    f:write(cert)
    f:close()
    f = assert(io.open("/tmp/pki_random.key", "w"))
    f:write(key)
    f:close()

    ngx.get_phase = mock_get_phase -- luacheck: ignore
    kong_clustering = clustering.new({
      role = "control_plane",
      cluster_mtls = "pki_check_cn",
      -- CN is server.kong_clustering_pki.domain
      cluster_cert = "/tmp/pki_random.crt",
      cluster_cert_key = "/tmp/pki_random.key",
      cluster_ocsp = "off",
    })
    ngx.get_phase = get_phase -- luacheck: ignore
  end)

  lazy_teardown(function()
    os.remove("/tmp/pki_random.crt")
    os.remove("/tmp/pki_random.key")
  end)

  -- FIXME: the description says the cert will be rejected, but the test
  -- logic is the opposite
  pending("rejects if client cert is a top level domain", function()
    local cert = create_self_signed("another.domain")
    local ok, _ = kong_clustering:validate_client_cert(cert)
    assert.is_truthy(ok)
  end)
end)

describe("hybrid mode validate client cert with cluster_allowed_common_names", function()

  local kong_clustering

  lazy_setup(function()
    local cert, key = create_self_signed("random.domain")
    local f = assert(io.open("/tmp/pki_random.crt", "w"))
    f:write(cert)
    f:close()
    f = assert(io.open("/tmp/pki_random.key", "w"))
    f:write(key)
    f:close()

    ngx.get_phase = mock_get_phase -- luacheck: ignore
    kong_clustering = clustering.new({
      role = "control_plane",
      cluster_mtls = "pki_check_cn",
      -- CN is server.kong_clustering_pki.domain
      cluster_cert = "/tmp/pki_random.crt",
      cluster_cert_key = "/tmp/pki_random.key",
      cluster_allowed_common_names = {"dp.kong_clustering_pki.domain", "another.domain"},
      cluster_ocsp = "off",
    })
    ngx.get_phase = get_phase -- luacheck: ignore
  end)

  lazy_teardown(function()
    os.remove("/tmp/pki_random.crt")
    os.remove("/tmp/pki_random.key")
  end)

  it("validates if client cert is in cluster_allowed_common_names", function()
    local cert = create_self_signed("dp.kong_clustering_pki.domain")
    local ok, err = kong_clustering:validate_client_cert(cert)
    assert.is_nil(err)
    assert.is_truthy(ok)
    cert = create_self_signed("another.domain")
    ok, err = kong_clustering:validate_client_cert(cert)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("rejects if client cert is not in cluster_allowed_common_names", function()
    local cert = create_self_signed("notmydp.kong_clustering_pki.domain")
    local ok, _ = kong_clustering:validate_client_cert(cert)
    assert.is_falsy(ok)
    cert = create_self_signed("yetanother.domain")
    ok, _ = kong_clustering:validate_client_cert(cert)
    assert.is_falsy(ok)
  end)
end)
