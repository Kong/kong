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
        "vaults",
      },
      nil, {
        "env",
        "mock",
      })

      assert(helpers.start_kong {
        database = strategy,
        prefix = helpers.test_conf.prefix,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        vaults = "env,mock",
      })

      client = assert(helpers.admin_client(10000))

      local res = client:put("/vaults/test-vault", {
        headers = { ["Content-Type"] = "application/json" },
        body = {
          name = "env",
        },
      })

      assert.res_status(200, res)

      local res = client:put("/vaults/mock-vault", {
        headers = { ["Content-Type"] = "application/json" },
        body = {
          name = "mock",
        },
      })

      assert.res_status(200, res)
    end)

    before_each(function()
      client = assert(helpers.admin_client(10000))
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
      local res, err = client:post("/certificates", {
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
      assert.is_nil(certificate["$refs"])

      certificate, err = db.certificates:select(certificate)
      assert.is_nil(err)
      assert.equal(ssl_fixtures.cert, certificate.cert)
      assert.equal(ssl_fixtures.key, certificate.key)
      assert.equal("{vault://test-vault/cert}", certificate["$refs"].cert)
      assert.equal("{vault://test-vault/key}", certificate["$refs"].key)
      assert.equal("{vault://unknown/cert}", certificate["$refs"].cert_alt)
      assert.equal("{vault://unknown/missing-key}", certificate["$refs"].key_alt)
      assert.equal("", certificate.cert_alt)
      assert.equal("", certificate.key_alt)

      -- process auto fields keeps the existing $refs
      local certificate_b = db.certificates.schema:process_auto_fields(certificate, "select")
      assert.same(certificate_b, certificate)

      -- TODO: this is unexpected but schema.process_auto_fields uses currently
      -- the `nulls` parameter to detect if the call comes from Admin API
      -- for performance reasons
      certificate, err = db.certificates:select(certificate, { nulls = true })
      assert.is_nil(err)
      assert.equal("{vault://test-vault/cert}", certificate.cert)
      assert.equal("{vault://test-vault/key}", certificate.key)
      assert.equal("{vault://unknown/cert}", certificate.cert_alt)
      assert.equal("{vault://unknown/missing-key}", certificate.key_alt)
      assert.is_nil(certificate["$refs"])

      -- verify that certificate attributes are of type reference when querying
      res, err = client:get("/certificates/"..certificate.id)
      assert.is_nil(err)
      body = assert.res_status(200, res)
      certificate = cjson.decode(body)
      assert.is_equal("{vault://test-vault/cert}", certificate.cert)
      assert.is_equal("{vault://test-vault/key}", certificate.key)
      assert.is_equal("{vault://unknown/cert}", certificate.cert_alt)
      assert.is_equal("{vault://unknown/missing-key}", certificate.key_alt)
      assert.is_nil(certificate["$refs"])
    end)

    it("create certificates with cert and key as secret using mock vault", function()
      local res, err = client:post("/certificates", {
        headers = { ["Content-Type"] = "application/json" },
        body = {
          cert     = "{vault://mock-vault/cert}",
          key      = "{vault://mock-vault/key}",
          cert_alt = "{vault://unknown/cert}",
          key_alt  = "{vault://unknown/missing-key}",
        },
      })
      assert.is_nil(err)
      local body = assert.res_status(201, res)
      local certificate = cjson.decode(body)
      assert.equal("{vault://mock-vault/cert}", certificate.cert)
      assert.equal("{vault://mock-vault/key}", certificate.key)
      assert.equal("{vault://unknown/cert}", certificate.cert_alt)
      assert.equal("{vault://unknown/missing-key}", certificate.key_alt)
      assert.is_nil(certificate["$refs"])

      certificate, err = db.certificates:select(certificate)
      assert.is_nil(err)
      assert.equal(ssl_fixtures.cert, certificate.cert)
      assert.equal(ssl_fixtures.key, certificate.key)
      assert.equal("{vault://mock-vault/cert}", certificate["$refs"].cert)
      assert.equal("{vault://mock-vault/key}", certificate["$refs"].key)
      assert.equal("{vault://unknown/cert}", certificate["$refs"].cert_alt)
      assert.equal("{vault://unknown/missing-key}", certificate["$refs"].key_alt)
      assert.equal("", certificate.cert_alt)
      assert.equal("", certificate.key_alt)

      -- TODO: this is unexpected but schema.process_auto_fields uses currently
      -- the `nulls` parameter to detect if the call comes from Admin API
      -- for performance reasons
      certificate, err = db.certificates:select(certificate, { nulls = true })
      assert.is_nil(err)
      assert.equal("{vault://mock-vault/cert}", certificate.cert)
      assert.equal("{vault://mock-vault/key}", certificate.key)
      assert.equal("{vault://unknown/cert}", certificate.cert_alt)
      assert.equal("{vault://unknown/missing-key}", certificate.key_alt)
      assert.is_nil(certificate["$refs"])

      -- verify that certificate attributes are of type reference when querying
      res, err = client:get("/certificates/"..certificate.id)
      assert.is_nil(err)
      body = assert.res_status(200, res)
      certificate = cjson.decode(body)
      assert.is_equal("{vault://mock-vault/cert}", certificate.cert)
      assert.is_equal("{vault://mock-vault/key}", certificate.key)
      assert.is_equal("{vault://unknown/cert}", certificate.cert_alt)
      assert.is_equal("{vault://unknown/missing-key}", certificate.key_alt)
      assert.is_nil(certificate["$refs"])
    end)

    it("generate correct cache key", function ()
      local cache_key = db.vaults:cache_key("test")
      assert.equal("vaults:test:::::", cache_key)
    end)
  end)
end
