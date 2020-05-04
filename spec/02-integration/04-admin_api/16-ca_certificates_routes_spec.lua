local ssl_fixtures = require "spec.fixtures.ssl"
local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("/ca_certificates with DB: #" .. strategy, function()
    local client, bp, db

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "ca_certificates",
      })

      assert(helpers.start_kong {
        database = strategy,
      })

      client = assert(helpers.admin_client(10000))
    end)

    it("GET", function()
      local res  = client:get("/ca_certificates")
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal(0, #json.data)

      res = client:post("/ca_certificates", {
        body    = {
          cert  = ssl_fixtures.cert_ca,
        },
        headers = { ["Content-Type"] = "application/json" },
      })

      assert.res_status(201, res)

      res  = client:get("/ca_certificates")
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.equal(1, #json.data)
      assert.equals(json.data[1].cert, ssl_fixtures.cert_ca)
    end)

    describe("POST", function()
      it("missing field", function()
        local res = client:post("/ca_certificates", {
          body    = { },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equal("schema violation (cert: required field missing)", json.message)
      end)

      it("non CA cert", function()
        local res = client:post("/ca_certificates", {
          body    = {
            cert = ssl_fixtures.cert,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equal("schema violation (certificate does not appear to be a CA because it is missing the \"CA\" basic constraint)", json.message)
      end)

      it("expired cert", function()
        local res = client:post("/ca_certificates", {
          body    = {
            cert = ssl_fixtures.cert_alt,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equal("schema violation (certificate expired, \"Not After\" time is in the past)", json.message)
      end)

      it("multiple certs", function()
        local res = client:post("/ca_certificates", {
          body    = {
            cert = ssl_fixtures.cert .. "\n" .. ssl_fixtures.cert,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equal("schema violation (please submit only one certificate at a time)", json.message)
      end)
    end)

    describe("DELETE", function()
      local ca

      lazy_setup(function()
        db:truncate("ca_certificates")
        ca = assert(bp.ca_certificates:insert())
      end)

      it("works", function()
        local res = client:delete("/ca_certificates/" .. ca.id)
        assert.res_status(204, res)

        res  = client:get("/ca_certificates")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(0, #json.data)
      end)
    end)

    describe("PATCH", function()
      local ca

      lazy_setup(function()
        db:truncate("ca_certificates")
        ca = assert(bp.ca_certificates:insert())
      end)

      it("non CA cert", function()
        local res = client:patch("/ca_certificates/" .. ca.id, {
          body    = {
            cert = ssl_fixtures.cert,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equal("schema violation (certificate does not appear to be a CA because it is missing the \"CA\" basic constraint)", json.message)
      end)

      it("expired cert", function()
        local res = client:patch("/ca_certificates/" .. ca.id, {
          body    = {
            cert = ssl_fixtures.cert_alt,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equal("schema violation (certificate expired, \"Not After\" time is in the past)", json.message)
      end)

      it("works", function()
        local res = client:patch("/ca_certificates/" .. ca.id, {
          body    = {
            cert = ssl_fixtures.cert_ca,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        assert.res_status(200, res)
      end)
    end)

    describe("PUT", function()
      local ca

      lazy_setup(function()
        db:truncate("ca_certificates")
        ca = assert(bp.ca_certificates:insert())
      end)

      it("missing field", function()
        local res = client:put("/ca_certificates/" .. ca.id, {
          body    = { },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equal("schema violation (cert: required field missing)", json.message)
      end)

      it("non CA cert", function()
        local res = client:put("/ca_certificates/" .. ca.id, {
          body    = {
            cert = ssl_fixtures.cert,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equal("schema violation (certificate does not appear to be a CA because it is missing the \"CA\" basic constraint)", json.message)
      end)

      it("expired cert", function()
        local res = client:put("/ca_certificates/" .. ca.id, {
          body    = {
            cert = ssl_fixtures.cert_alt,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equal("schema violation (certificate expired, \"Not After\" time is in the past)", json.message)
      end)

      it("updates existing cert", function()
        local res = client:put("/ca_certificates/" .. ca.id, {
          body    = {
            cert = ssl_fixtures.cert_ca,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        assert.res_status(200, res)

        res  = client:get("/ca_certificates")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(1, #json.data)
        assert.equals(json.data[1].cert, ssl_fixtures.cert_ca)
      end)

      it("creates new cert when uuid does not exist", function()
        db:truncate("ca_certificates")

        local res = client:put("/ca_certificates/123e4567-e89b-12d3-a456-426655440000", {
          body    = {
            cert = ssl_fixtures.cert_ca,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        assert.res_status(200, res)

        local res  = client:get("/ca_certificates/123e4567-e89b-12d3-a456-426655440000")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(ssl_fixtures.cert_ca, json.cert)
      end)
    end)

    lazy_teardown(function()
      if client then client:close() end
      helpers.stop_kong()
    end)
  end)
end
