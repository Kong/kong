local ssl_fixtures = require "spec.fixtures.ssl"
local helpers = require "spec.helpers"
local cjson = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("/certificates with DB: #" .. strategy, function()
    local client
    local db

    lazy_setup(function()
      helpers.setenv("CERT", ssl_fixtures.cert)
      helpers.setenv("KEY", ssl_fixtures.key)

      local _
      _, db = helpers.get_db_utils(strategy, {
        "certificates",
        "vaults_beta",
      })

      assert(helpers.start_kong {
        database = strategy,
        vaults = "env",
      })

      client = assert(helpers.admin_client(10000))

      local res = client:put("/vaults-beta/test-vault", {
        headers = { ["Content-Type"] = "application/json" },
        body = {
          name = "env",
        },
      })

      assert.res_status(200, res)
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.unsetenv("CERT")
      helpers.unsetenv("KEY")
    end)

    it("create certificates with cert and key as secret", function()
      local res, err  = client:post("/certificates", {
        headers = { ["Content-Type"] = "application/json" },
        body = {
          cert     = "{vault://test-vault/cert}",
          key      = "{vault://test-vault/key}",
          cert_alt = "{vault://unknown/cert}",
          key_alt  = "{vault://unknown/missing-key}",
        },
      })
      assert.is_nil(err)
      local body = assert.res_status(201, res)
      local certificate = cjson.decode(body)
      assert.equal("{vault://test-vault/cert}", certificate.cert)
      assert.equal("{vault://test-vault/key}", certificate.key)
      assert.equal("{vault://unknown/cert}", certificate.cert_alt)
      assert.equal("{vault://unknown/missing-key}", certificate.key_alt)

      certificate, err = db.certificates:select({ id = certificate.id })
      assert.is_nil(err)
      assert.equal(ssl_fixtures.cert, certificate.cert)
      assert.equal(ssl_fixtures.key, certificate.key)
      assert.is_nil(certificate.cert_alt)
      assert.is_nil(certificate.key_alt)

      -- TODO: this is unexpected but schema.process_auto_fields uses currently
      -- the `nulls` parameter to detect if the call comes from Admin API
      -- for performance reasons
      certificate, err = db.certificates:select({ id = certificate.id }, { nulls = true })
      assert.is_nil(err)
      assert.equal("{vault://test-vault/cert}", certificate.cert)
      assert.equal("{vault://test-vault/key}", certificate.key)
      assert.equal("{vault://unknown/cert}", certificate.cert_alt)
      assert.equal("{vault://unknown/missing-key}", certificate.key_alt)
    end)
  end)
end
