local ssl_fixtures = require "spec.fixtures.ssl"
local helpers = require "spec.helpers"
local cjson = require "cjson"


local ca_cert = [[
-----BEGIN CERTIFICATE-----
MIIEvjCCAqagAwIBAgIJALabx/Nup200MA0GCSqGSIb3DQEBCwUAMBMxETAPBgNV
BAMMCFlvbG80Mi4xMCAXDTE5MDkxNTE2Mjc1M1oYDzIxMTkwODIyMTYyNzUzWjAT
MREwDwYDVQQDDAhZb2xvNDIuMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
ggIBANIW67Ay0AtTeBY2mORaGet/VPL5jnBRz0zkZ4Jt7fEq3lbxYaJBnFI8wtz3
bHLtLsxkvOFujEMY7HVd+iTqbJ7hLBtK0AdgXDjf+HMmoWM7x0PkZO+3XSqyRBbI
YNoEaQvYBNIXrKKJbXIU6higQaXYszeN8r3+RIbcTIlZxy28msivEGfGTrNujQFc
r/eyf+TLHbRqh0yg4Dy/U/T6fqamGhFrjupRmOMugwF/BHMH2JHhBYkkzuZLgV2u
7Yh1S5FRlh11am5vWuRSbarnx72hkJ99rUb6szOWnJKKew8RSn3CyhXbS5cb0QRc
ugRc33p/fMucJ4mtCJ2Om1QQe83G1iV2IBn6XJuCvYlyWH8XU0gkRxWD7ZQsl0bB
8AFTkVsdzb94OM8Y6tWI5ybS8rwl8b3r3fjyToIWrwK4WDJQuIUx4nUHObDyw+KK
+MmqwpAXQWbNeuAc27FjuJm90yr/163aGuInNY5Wiz6CM8WhFNAi/nkEY2vcxKKx
irSdSTkbnrmLFAYrThaq0BWTbW2mwkOatzv4R2kZzBUOiSjRLPnbyiPhI8dHLeGs
wMxiTXwyPi8iQvaIGyN4DPaSEiZ1GbexyYFdP7sJJD8tG8iccbtJYquq3cDaPTf+
qv5M6R/JuMqtUDheLSpBNK+8vIe5e3MtGFyrKqFXdynJtfHVAgMBAAGjEzARMA8G
A1UdEwQIMAYBAf8CAQAwDQYJKoZIhvcNAQELBQADggIBAK0BmL5B1fPSMbFy8Hbc
/ESEunt4HGaRWmZZSa/aOtTjhKyDXLLJZz3C4McugfOf9BvvmAOZU4uYjfHTnNH2
Z3neBkdTpQuJDvrBPNoCtJns01X/nuqFaTK/Tt9ZjAcVeQmp51RwhyiD7nqOJ/7E
Hp2rC6gH2ABXeexws4BDoZPoJktS8fzGWdFBCHzf4mCJcb4XkI+7GTYpglR818L3
dMNJwXeuUsmxxKScBVH6rgbgcEC/6YwepLMTHB9VcH3X5VCfkDIyPYLWmvE0gKV7
6OU91E2Rs8PzbJ3EuyQpJLxFUQp8ohv5zaNBlnMb76UJOPR6hXfst5V+e7l5Dgwv
Dh4CeO46exmkEsB+6R3pQR8uOFtubH2snA0S3JA1ji6baP5Y9Wh9bJ5McQUgbAPE
sCRBFoDLXOj3EgzibohC5WrxN3KIMxlQnxPl3VdQvp4gF899mn0Z9V5dAsGPbxRd
quE+DwfXkm0Sa6Ylwqrzu2OvSVgbMliF3UnWbNsDD5KcHGIaFxVC1qkwK4cT3pyS
58i/HAB2+P+O+MltQUDiuw0OSUFDC0IIjkDfxLVffbF+27ef9C5NG81QlwTz7TuN
zeigcsBKooMJTszxCl6dtxSyWTj7hJWXhy9pXsm1C1QulG6uT4RwCa3m0QZoO7G+
6Wu6lP/kodPuoNubstIuPdi2
-----END CERTIFICATE-----
]]


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
      it("succeeds", function()
        local res = client:post("/ca_certificates", {
          body    = {
            cert = ca_cert,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        assert.res_status(201, res)
      end)

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
