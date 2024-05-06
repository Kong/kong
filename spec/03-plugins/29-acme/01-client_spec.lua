local util = require("resty.acme.util")

local helpers = require "spec.helpers"
local cjson = require "cjson"

local pkey = require("resty.openssl.pkey")
local x509 = require("resty.openssl.x509")

local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy

local client

local function new_cert_key_pair(expire)
  local key = pkey.new(nil, 'EC', 'prime256v1')
  local crt = x509.new()
  crt:set_pubkey(key)
  crt:set_version(3)
  if expire then
    crt:set_not_after(expire)
  end
  crt:sign(key)
  return key:to_PEM("private"), crt:to_PEM()
end

local strategies = {}
for _, strategy in helpers.each_strategy() do
  table.insert(strategies, strategy)
end
table.insert(strategies, "off")

local proper_config = {
  account_email = "someone@somedomain.com",
  api_uri = "http://api.someacme.org",
  storage = "shm",
  storage_config = {
    shm = { shm_name = "kong" },
  },
  renew_threshold_days = 30,
}

for _, strategy in ipairs(strategies) do
  local _, db

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
      assert.equal(err, "shm is not defined in plugin storage config")
    end)

    it("creates acme client properly", function()
      local c, err = client.new(proper_config)
      assert.is_nil(err)
      assert.not_nil(c)
    end)
  end)
end

for _, strategy in ipairs(strategies) do
  local account_name, account_key
  local c, config, db

  local KEY_ID = "123"
  local KEY_SET_NAME = "key_set_foo"

  local pem_pub, pem_priv = helpers.generate_keys("PEM")

  lazy_setup(function()
    client = require("kong.plugins.acme.client")
    account_name = client._account_name(proper_config)
  end)

  describe("Plugin: acme (client.create_account) [#" .. strategy .. "]", function()
    describe("create with preconfigured account_key with key_set", function()
      lazy_setup(function()
        account_key = {key_id = KEY_ID, key_set = KEY_SET_NAME}
        config = cycle_aware_deep_copy(proper_config)
        config.account_key = account_key
        c = client.new(config)

        _, db = helpers.get_db_utils(strategy ~= "off" and strategy or nil, {"keys", "key_sets"})

        local ks, err = assert(db.key_sets:insert({name = KEY_SET_NAME}))
        assert.is_nil(err)

        local k, err = db.keys:insert({
          name = "Test PEM",
          pem = {
            private_key = pem_priv,
            public_key = pem_pub
          },
          set = ks,
          kid = KEY_ID
        })
        assert(k)
        assert.is_nil(err)
      end)

      lazy_teardown(function()
        c.storage:delete(account_name)
      end)

      -- The first call should result in the account key being persisted.
      it("persists account", function()
        local err = client._create_account(config)
        assert.is_nil(err)

        local account, err = c.storage:get(account_name)
        assert.is_nil(err)
        assert.not_nil(account)

        local account_data = cjson.decode(account)
        assert.equal(account_data.key, pem_priv)
      end)

      -- The second call should be a nop because the key is found in the db.
      -- Validate that the second call does not result in the key being changed.
      it("skips persisting existing account", function()
        local err = client._create_account(config)
        assert.is_nil(err)

        local account, err = c.storage:get(account_name)
        assert.is_nil(err)
        assert.not_nil(account)

        local account_data = cjson.decode(account)
        assert.equal(account_data.key, pem_priv)
      end)
    end)

    describe("create with preconfigured account_key without key_set", function()
      lazy_setup(function()
        account_key = {key_id = KEY_ID}
        config = cycle_aware_deep_copy(proper_config)
        config.account_key = account_key
        c = client.new(config)

        _, db = helpers.get_db_utils(strategy ~= "off" and strategy or nil, {"keys", "key_sets"})

        local k, err = db.keys:insert({
          name = "Test PEM",
          pem = {
            private_key = pem_priv,
            public_key = pem_pub
          },
          kid = KEY_ID
        })
        assert(k)
        assert.is_nil(err)
      end)

      lazy_teardown(function()
        c.storage:delete(account_name)
      end)

      -- The first call should result in the account key being persisted.
      it("persists account", function()
        local err = client._create_account(config)
        assert.is_nil(err)

        local account, err = c.storage:get(account_name)
        assert.is_nil(err)
        assert.not_nil(account)

        local account_data = cjson.decode(account)
        assert.equal(account_data.key, pem_priv)
      end)
    end)

    describe("create with generated account_key", function()
      local i = 1
      local account_keys = {}

      lazy_setup(function()
        config = cycle_aware_deep_copy(proper_config)
        c = client.new(config)

        account_keys[1] = util.create_pkey()
        account_keys[2] = util.create_pkey()

        util.create_pkey = function(size, type)
          local key = account_keys[i]
          i = i + 1
          return key
        end
      end)

      lazy_teardown(function()
        c.storage:delete(account_name)
      end)

      -- The first call should result in a key being generated and the account
      -- should then be persisted.
      it("persists account", function()
        local err = client._create_account(config)
        assert.is_nil(err)

        local account, err = c.storage:get(account_name)
        assert.is_nil(err)
        assert.not_nil(account)

        local account_data = cjson.decode(account)
        assert.equal(account_data.key, account_keys[1])
      end)

      -- The second call should be a nop because the key is found in the db.
      it("skip persisting existing account", function()
        local err = client._create_account(config)
        assert.is_nil(err)

        local account, err = c.storage:get(account_name)
        assert.is_nil(err)
        assert.not_nil(account)

        local account_data = cjson.decode(account)
        assert.equal(account_data.key, account_keys[1])
      end)
    end)
  end)
end

for _, strategy in helpers.each_strategy() do
  describe("Plugin: acme (client.save) [#" .. strategy .. "]", function()
    local bp, db
    local cert, sni
    local host = "test1.test"

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
      local new_host = "test2.test"

      it("returns no error", function()
        err = client._save_dao(new_host, key, crt)
        assert.is_nil(err)
      end)

      it("create new sni", function()
        new_sni, err = db.snis:select_by_name(new_host)
        assert.is_nil(err)
        assert.not_nil(new_sni.certificate.id)
      end)

      it("create new certificate", function()
        new_cert, err = db.certificates:select(new_sni.certificate)
        assert.is_nil(err)
        assert.same(new_cert.key, key)
        assert.same(new_cert.cert, crt)
      end)
    end)

    describe("update", function()
      local key, crt = new_cert_key_pair()
      local new_sni, new_cert, err

      it("returns no error", function()
        err = client._save_dao(host, key, crt)
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
        new_cert, err = db.certificates:select(new_sni.certificate)
        assert.is_nil(err)
        assert.same(new_cert.key, key)
        assert.same(new_cert.cert, crt)
      end)

      it("deletes old certificate", function()
        new_cert, err = db.certificates:select(cert)
        assert.is_nil(err)
        assert.is_nil(new_cert)
      end)
    end)
  end)
end

for _, strategy in ipairs({"off"}) do
  describe("Plugin: acme (client.renew) [#" .. strategy .. "]", function()
    local bp
    local cert
    local host = "test1.test"
    local host_not_expired = "test2.test"
    -- make it due for renewal
    local key, crt = new_cert_key_pair(ngx.time() - 23333)
    -- make it not due for renewal
    local key_not_expired, crt_not_expired = new_cert_key_pair(ngx.time() + 365 * 86400)

    lazy_setup(function()
      bp, _ = helpers.get_db_utils(strategy, {
        "certificates",
        "snis",
      }, { "acme", })

      cert = bp.certificates:insert {
        cert = crt,
        key = key,
        tags = { "managed-by-acme" },
      }

      bp.snis:insert {
        name = host,
        certificate = cert,
        tags = { "managed-by-acme" },
      }

      cert = bp.certificates:insert {
        cert = crt_not_expired,
        key = key_not_expired,
        tags = { "managed-by-acme" },
      }

      bp.snis:insert {
        name = host_not_expired,
        certificate = cert,
        tags = { "managed-by-acme" },
      }

      client = require("kong.plugins.acme.client")
      -- hack in unit test mode
      client._set_is_dbless(strategy == "off")
    end)

    describe("", function()
      it("deletes renew config is cert is deleted", function()
        local c, err = client.new(proper_config)
        assert.is_nil(err)

        local host = "dne.konghq.com"
        -- write a dummy renew config
        err = c.storage:set(client._renew_key_prefix .. host, cjson.encode({
          host = host,
          -- make it due for renewal
          expire_at = ngx.time() - 23333,
        }))
        assert.is_nil(err)
        -- do the renewal
        err = client._renew_certificate_storage(proper_config)
        assert.is_nil(err)
        -- the dummy config should now be deleted
        local v, err = c.storage:get(client._renew_key_prefix .. host)
        assert.is_nil(err)
        assert.is_nil(v)
      end)

      it("renews a certificate when it's expired", function()
        local c, err = client.new(proper_config)

        assert.is_nil(err)
        if strategy == "off" then
          err = c.storage:set(client._certkey_key_prefix .. host, cjson.encode({
            cert = crt,
            key = key,
          }))
          assert.is_nil(err)
        end

        local certkey, err = client.load_certkey(proper_config, host)
        assert.is_nil(err)
        assert.not_nil(certkey)
        assert.not_nil(certkey.cert)
        assert.not_nil(certkey.key)
        -- check renewal
        local renew, err = client._check_expire(certkey.cert, 30 * 86400)
        assert.is_nil(err)
        assert.is_truthy(renew)
      end)

      it("does not renew a certificate when it's not expired", function()
        local c, err = client.new(proper_config)

        assert.is_nil(err)
        if strategy == "off" then
          err = c.storage:set(client._certkey_key_prefix .. host_not_expired, cjson.encode({
            cert = crt_not_expired,
            key = key_not_expired,
          }))
          assert.is_nil(err)
        end

        local certkey, err = client.load_certkey(proper_config, host_not_expired)
        assert.is_nil(err)
        assert.not_nil(certkey)
        assert.not_nil(certkey.cert)
        assert.not_nil(certkey.key)
        -- check renewal
        local renew, err = client._check_expire(certkey.cert, 30 * 86400)
        assert.is_nil(err)
        assert.is_falsy(renew)
      end)

      it("calling handler.renew with a false argument should be successful", function()
        local handler = require("kong.plugins.acme.handler")
        handler:configure({{domains = {"example.com"}}})

        local original = client.renew_certificate
        client.renew_certificate = function (config)
          print("mock renew_certificate")
        end
        handler.renew(false)
        client.renew_certificate = original
      end)
    end)

  end)
end
