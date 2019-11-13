local client = require("kong.plugins.letsencrypt.client")
local util = require("resty.acme.util")

local helpers = require "spec.helpers"

local pkey = require("resty.openssl.pkey")
local x509 = require("resty.openssl.x509")

local function new_cert_key_pair()
  local key = pkey.new(nil, 'EC', 'prime256v1')
  local crt = x509.new()
  crt:set_pubkey(key)
  crt:set_version(3)
  crt:sign(key)
  return key:to_PEM("private"), crt:to_PEM()
end

describe("Plugin: letsencrypt (client.new)", function()
  it("rejects invalid storage config", function()
    local c, err = client.new({
      storage = "shm",
      storage_config = {
        shm = nil,
      }
    })
    assert.is_nil(c)
    assert.equal(err, "shm is not defined in plugin storage config")
  end)

  it("creates acme client properly", function()
    local c, err = client.new({
      account_key = util.create_pkey(),
      account_email = "someone@somedomain.com",
      storage = "shm",
      storage_config = {
        shm = { shm_name = "kong" },
      }
    })
    assert.is_nil(err)
    assert.not_nil(c)
  end)
end)

for _, strategy in helpers.each_strategy() do
  describe("Plugin: letsencrypt (client.save) [#" .. strategy .. "]", function()
    local bp, db
    local cert, sni
    local host = "test1.com"

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "certificates",
        "snis",
      }, { "letsencrypt", })

      local key, crt = new_cert_key_pair()
      cert = bp.certificates:insert {
        cert = crt,
        key = key,
        tags = { "managed-by-letsencrypt" },
      }

      sni = bp.snis:insert {
        name = host,
        certificate = cert,
        tags = { "managed-by-letsencrypt" },
      }

    end)

    describe("creates new cert", function()
      local key, crt = new_cert_key_pair()
      local new_sni, new_cert, err
      local new_host = "test2.com"

      it("returns no error", function()
        err = client._save(new_host, key, crt)
        assert.is_nil(err)
      end)

      it("create new sni", function()
        new_sni, err = db.snis:select_by_name(new_host)
        assert.is_nil(err)
        assert.not_nil(new_sni.certificate.id)
      end)

      it("create new certificate", function()
        new_cert, err = db.certificates:select({ id = new_sni.certificate.id })
        assert.is_nil(err)
        assert.same(new_cert.key, key)
        assert.same(new_cert.cert, crt)
      end)
    end)

    describe("update", function()
      local key, crt = new_cert_key_pair()
      local new_sni, new_cert, err

      it("returns no error", function()
        err = client._save(host, key, crt)
        assert.is_nil(err)
      end)

      it("updates existing sni", function()
        new_sni, err = db.snis:select_by_name(host)
        assert.is_nil(err)
        assert.same(new_sni.id, sni.id)
        assert.not_nil(new_sni.certificate.id)
        assert.not_same(new_sni.certificate.id, sni.certificate.id)
      end)

      it("creates new certificate", function()
        new_cert, err = db.certificates:select({ id = new_sni.certificate.id })
        assert.is_nil(err)
        assert.same(new_cert.key, key)
        assert.same(new_cert.cert, crt)
      end)

      it("deletes old certificate", function()
        new_cert, err = db.certificates:select({ id = cert.id })
        assert.is_nil(err)
        assert.is_nil(new_cert)
      end)
    end)

  end)
end
