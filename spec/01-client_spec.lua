local util = require("resty.acme.util")

local helpers = require "spec.helpers"

local pkey = require("resty.openssl.pkey")
local x509 = require("resty.openssl.x509")

local client

local function new_cert_key_pair()
  local key = pkey.new(nil, 'EC', 'prime256v1')
  local crt = x509.new()
  crt:set_pubkey(key)
  crt:set_version(3)
  crt:sign(key)
  return key:to_PEM("private"), crt:to_PEM()
end

local strategies = {}
for _, strategy in helpers.each_strategy() do
  table.insert(strategies, strategy)
end
table.insert(strategies, "off")

for _, strategy in ipairs(strategies) do
  local _, db

  local proper_config = {
    account_email = "someone@somedomain.com",
    api_uri = "http://api.acme.org",
    storage = "shm",
    storage_config = {
      shm = { shm_name = "kong" },
    }
  }

  lazy_setup(function()
    _, db = helpers.get_db_utils(strategy, {
      "acme_storage"
    }, { "acme", })

    client = require("kong.plugins.acme.client")

    local account_name = client._account_name(proper_config)

    local fake_cache = {
      [account_name] = {
        key = util.create_pkey(),
        kid = "fake kid url",
      },
    }

    kong.cache = {
      get = function(_, _, _, f, _, k)
        return fake_cache[k]
      end
    }

    db.acme_storage:insert {
      key = account_name,
      value = fake_cache[account_name],
    }

  end)

  describe("Plugin: acme (client.new) [#" .. strategy .. "]", function()
    it("rejects invalid account config", function()
      local c, err = client.new({
        storage = "shm",
        storage_config = {
          shm = nil,
        },
        api_uri = proper_config.api_uri,
        account_email = "notme@exmaple.com",
      })
      assert.is_nil(c)
      assert.equal(err, "account notme@exmaple.com not found in storage")
    end)

    it("creates acme client properly", function()
      local c, err = client.new(proper_config)
      assert.is_nil(err)
      assert.not_nil(c)
    end)
  end)
end

for _, strategy in helpers.each_strategy() do
  describe("Plugin: acme (client.save) [#" .. strategy .. "]", function()
    local bp, db
    local cert, sni
    local host = "test1.com"

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "certificates",
        "snis",
      }, { "acme", })

      local key, crt = new_cert_key_pair()
      cert = bp.certificates:insert {
        cert = crt,
        key = key,
        tags = { "managed-by-acme" },
      }

      sni = bp.snis:insert {
        name = host,
        certificate = cert,
        tags = { "managed-by-acme" },
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
