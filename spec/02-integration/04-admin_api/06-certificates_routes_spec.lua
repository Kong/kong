local ssl_fixtures = require "spec.fixtures.ssl"
local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local Errors  = require "kong.db.errors"


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_multipart = fn("multipart/form-data")
  local test_json = fn("application/json")

  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with multipart/form-data", test_multipart)
  it(title .. " with application/json", test_json)
end


local get_name
do
  local n = 0
  get_name = function()
    n = n + 1
    return string.format("name%04d.test", n)
  end
end


for _, strategy in helpers.each_strategy() do

describe("Admin API: #" .. strategy, function()
  local client

  local function add_certificate()
    local n1 = get_name()
    local n2 = get_name()
    local names = { n1, n2 }

    local res = client:post("/certificates", {
      body    = {
        cert  = ssl_fixtures.cert,
        key   = ssl_fixtures.key,
        snis  = names,
      },
      headers = { ["Content-Type"] = "application/json" },
    })

    local body = assert.res_status(201, res)
    local certificate = cjson.decode(body)
    return certificate, names
  end

  local function get_certificates()
    local res  = client:get("/certificates")
    local body = assert.res_status(200, res)
    return cjson.decode(body)
  end

  local bp, db

  before_each(function()
    client = assert(helpers.admin_client())
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  lazy_setup(function()
    bp, db = helpers.get_db_utils(strategy, {
      "certificates",
      "snis",
    })

    assert(helpers.start_kong({
      database = strategy,
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  describe("/certificates", function()

    describe("GET", function()

      it("retrieves all certificates with snis", function()

        local my_snis = {}
        for i = 1, 150 do
          table.insert(my_snis, string.format("my-sni-%03d.test", i))
        end

        local res = client:post("/certificates", {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = my_snis,
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        assert.res_status(201, res)

        local json = get_certificates()
        assert.equal(1, #json.data)
        assert.is_string(json.data[1].cert)
        assert.is_string(json.data[1].key)
        assert.same(my_snis, json.data[1].snis)
      end)
    end)

    describe("POST", function()

      it("returns a conflict when duplicated snis are present in the request", function()
        local n1 = get_name()
        local n2 = get_name()
        local res = client:post("/certificates", {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { n1, n2, n1 },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equals("schema violation (snis: " .. n1 .. " is duplicated)", json.message)

        -- make sure we didnt add the certificate, or any snis
        local json = get_certificates()
        for _, data in ipairs(json.data) do
          for _, sni in ipairs(data.snis) do
            assert.not_equal(n1, sni)
            assert.not_equal(n2, sni)
          end
        end
      end)

      it("returns a conflict when a pre-existing sni is detected", function()
        local n1 = get_name()
        local n2 = get_name()
        local res = client:post("/certificates", {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { n1 },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        assert.res_status(201, res)

        local res = client:post("/certificates", {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { n1, n2 },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.matches("snis: " .. n1 .. " already associated with existing certificate", json.message)

        -- make sure we didnt add the certificate, or any snis
        local json = get_certificates()
        for _, data in ipairs(json.data) do
          for _, sni in ipairs(data.snis) do
            assert.not_equal(n2, sni)
          end
        end
      end)

      it_content_types("creates a certificate and returns it with the snis pseudo-property", function(content_type)
        return function()
          local n1 = get_name()
          local n2 = get_name()

          local body
          if content_type == "multipart/form-data" then
            body = {
              cert        = ssl_fixtures.cert,
              key         = ssl_fixtures.key,
              ["snis[1]"] = n1,
              ["snis[2]"] = n2,
            }
          elseif content_type == "application/x-www-form-urlencoded" then
            body = {
              cert = require "socket.url".escape(ssl_fixtures.cert),
              key  = require "socket.url".escape(ssl_fixtures.key),
              snis = { n1, n2 }
            }
          else
            body = {
              cert = ssl_fixtures.cert,
              key  = ssl_fixtures.key,
              snis = { n1, n2 }
            }
          end

          local res = client:post("/certificates", {
            body    = body,
            headers = { ["Content-Type"] = content_type },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.is_string(json.cert)
          assert.is_string(json.key)
          assert.same({ n1, n2 }, json.snis)
        end
      end)

      it_content_types("returns snis as [] when none is set", function(content_type)
        return function()
          local body
          if content_type == "application/x-www-form-urlencoded" then
            body = {
              cert = require "socket.url".escape(ssl_fixtures.cert),
              key  = require "socket.url".escape(ssl_fixtures.key),
            }
          else
            body = {
              cert = ssl_fixtures.cert,
              key  = ssl_fixtures.key,
            }
          end

          local res = client:post("/certificates", {
            body    = body,
            headers = { ["Content-Type"] = content_type },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.is_string(json.cert)
          assert.is_string(json.key)
          assert.matches('"snis":[]', body, nil, true)
        end
      end)
    end)
  end)

  describe("/certificates/cert_id_or_sni", function()

    describe("GET", function()
      it("retrieves a certificate by id", function()
        local certificate, names = add_certificate()
        local res1  = client:get("/certificates/" .. certificate.id)
        local body1 = assert.res_status(200, res1)
        local json1 = cjson.decode(body1)

        assert.is_string(json1.cert)
        assert.is_string(json1.key)
        assert.same(names, json1.snis)
      end)

      it("retrieves a certificate by sni", function()
        local _, names = add_certificate()
        local res1  = client:get("/certificates/" .. names[1])
        local body1 = assert.res_status(200, res1)
        local json1 = cjson.decode(body1)

        local res2  = client:get("/certificates/" .. names[2])
        local body2 = assert.res_status(200, res2)
        local json2 = cjson.decode(body2)

        assert.is_string(json1.cert)
        assert.is_string(json1.key)
        assert.same(names, json1.snis)
        assert.same(json1, json2)
      end)

      it("returns 404 for a random non-existing uuid", function()
        local res = client:get("/certificates/" .. utils.uuid())
        assert.res_status(404, res)
      end)

      it("returns 404 for a random non-existing sni", function()
        local res = client:get("/certificates/doesntexist.com")
        assert.res_status(404, res)
      end)
    end)

    describe("PUT", function()
      it("creates if not found", function()
        local n1 = get_name()
        local id = utils.uuid()
        local res = client:put("/certificates/" .. id, {
          body = {
            cert = ssl_fixtures.cert,
            key = ssl_fixtures.key,
            snis = { n1 },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(ssl_fixtures.cert, json.cert)

        assert.same({ n1 }, json.snis)
        json.snis = nil

        local in_db = assert(db.certificates:select({ id = id }, { nulls = true }))
        assert.same(json, in_db)
      end)

      it("creates a new sni when provided in the url", function()
        local n1 = get_name()
        local n2 = get_name()
        local res = client:put("/certificates/" .. n1, {
          body = {
            cert = ssl_fixtures.cert,
            key = ssl_fixtures.key,
            snis = { n2 },
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(ssl_fixtures.cert, json.cert)

        assert.same({ n1, n2 }, json.snis)
        json.snis = nil

        local in_db = assert(db.certificates:select({ id = json.id }, { nulls = true }))
        assert.same(json, in_db)
      end)

      it("creates a new sni when provided in the url (with sni duplicated in url and body)", function()
        local n1 = get_name()
        local n2 = get_name()
        local res = client:put("/certificates/" .. n1, {
          body = {
            cert = ssl_fixtures.cert,
            key = ssl_fixtures.key,
            snis = { n1, n2 },
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(ssl_fixtures.cert, json.cert)

        assert.same({ n1, n2 }, json.snis)
        json.snis = nil

        local in_db = assert(db.certificates:select({ id = json.id }, { nulls = true }))
        assert.same(json, in_db)
      end)

      it("upserts if found", function()
        local certificate = add_certificate()

        local res = client:put("/certificates/" .. certificate.id, {
          body = { cert = ssl_fixtures.cert_alt, key = ssl_fixtures.key_alt },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(ssl_fixtures.cert_alt, json.cert)
        assert.same(ssl_fixtures.key_alt, json.key)
        assert.same({}, json.snis)

        json.snis = nil

        local in_db = assert(db.certificates:select({ id = certificate.id }, { nulls = true }))
        assert.same(json, in_db)
      end)

      it("handles invalid input", function(content_type)
        -- Missing params
        local res = client:put("/certificates/" .. utils.uuid(), {
          body = {},
          headers = { ["Content-Type"] = content_type }
        })
        local body = assert.res_status(400, res)
        assert.same({
          code     = Errors.codes.SCHEMA_VIOLATION,
          name     = "schema violation",
          message  = "2 schema violations (cert: required field missing; key: required field missing)",
          fields  = {
            cert = "required field missing",
            key = "required field missing",
          }
        }, cjson.decode(body))
      end)

      it("handles mismatched keys/certificates", function()
        local res = client:post("/certificates", {
          body = {
            cert = ssl_fixtures.cert,
            key = ssl_fixtures.key_alt,
          },
          headers = { ["Content-Type"] = "application/json" }
        })
        local body = assert.res_status(400, res)
        assert.same({
          code     = Errors.codes.SCHEMA_VIOLATION,
          name     = "schema violation",
          message  = "schema violation (certificate does not match key)",
          fields  = {
            ["@entity"] = { "certificate does not match key" },
          }
        }, cjson.decode(body))
      end)
    end)

    describe("PATCH", function()

      it_content_types("updates a certificate by cert id", function(content_type)
        return function()
          local certificate = add_certificate()

          local body
          if content_type == "application/x-www-form-urlencoded" then
            body = {
              cert = require "socket.url".escape(ssl_fixtures.cert_alt),
              key  = require "socket.url".escape(ssl_fixtures.key_alt),
            }
          else
            body = {
              cert = ssl_fixtures.cert_alt,
              key  = ssl_fixtures.key_alt,
            }
          end

          local res = client:patch("/certificates/" .. certificate.id, {
            body = body,
            headers = { ["Content-Type"] = content_type }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(ssl_fixtures.cert_alt, json.cert)
        end
      end)

      it_content_types("update by id returns full certificate", function(content_type)
        return function()
          local certificate = add_certificate()

          local res = client:patch("/certificates/" .. certificate.id, {
            body = {},
            headers = { ["Content-Type"] = content_type }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.same(certificate, json)
        end
      end)

      it_content_types("updates a certificate by sni", function(content_type)
        return function()
          local _, names = add_certificate()

          local body
          if content_type == "application/x-www-form-urlencoded" then
            body = {
              cert = require "socket.url".escape(ssl_fixtures.cert_alt),
              key  = require "socket.url".escape(ssl_fixtures.key_alt),
            }
          else
            body = {
              cert = ssl_fixtures.cert_alt,
              key  = ssl_fixtures.key_alt,
            }
          end

          local res = client:patch("/certificates/" .. names[1], {
            body = body,
            headers = { ["Content-Type"] = content_type }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(ssl_fixtures.cert_alt, json.cert)
        end
      end)

      it_content_types("update by sni returns full certificate", function(content_type)
        return function()
          local certificate, names = add_certificate()

          local res = client:patch("/certificates/" .. names[1], {
            body = {},
            headers = { ["Content-Type"] = content_type }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.same(certificate, json)
        end
      end)

      it("returns 404 for a random non-existing id", function()
        local n1 = get_name()
        local res = client:patch("/certificates/" .. utils.uuid(), {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { n1 },
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        assert.res_status(404, res)

        -- make sure we did not add any certificate or sni
        local json = get_certificates()
        for _, data in ipairs(json.data) do
          for _, sni in ipairs(data.snis) do
            assert.not_equal(n1, sni)
          end
        end
      end)

      it("updates snis associated with a certificate", function()
        local certificate = add_certificate()
        local n1 = get_name()

        local json_before = get_certificates()

        local res = client:patch("/certificates/" .. certificate.id, {
          body    = { snis = { n1 }, },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same({ n1 }, json.snis)

        -- make sure we did not add any certificate, and that the snis
        -- are correct
        local json = get_certificates()
        assert.equal(#json_before.data, #json.data)
        for i, data in ipairs(json.data) do
          if data.id == certificate.id then
            assert.same({ n1 }, data.snis)
          else
            assert.same(json_before.data[i].snis, data.snis)
          end
        end
      end)

      it("updates only the certificate if no snis are specified", function()
        local certificate, names = add_certificate()

        local json_before = get_certificates()

        local res = client:patch( "/certificates/" .. certificate.id, {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- make sure certificate got updated and sni remains the same
        assert.same(names, json.snis)
        assert.same(ssl_fixtures.cert, json.cert)
        assert.same(ssl_fixtures.key, json.key)

        -- make sure the certificate got updated in DB
        res  = client:get("/certificates/" .. certificate.id)
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(ssl_fixtures.cert, json.cert)
        assert.equal(ssl_fixtures.key, json.key)

        -- make sure we did not add any certificate or sni
        local json = get_certificates()
        assert.same(json_before, json)
      end)

      it("returns a conflict when duplicated snis are present in the request", function()
        local certificate = add_certificate()
        local json_before = get_certificates()
        local n1 = get_name()

        local res = client:patch("/certificates/" .. certificate.id, {
          body    = {
            snis  = { n1, n1 },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("schema violation (snis: " .. n1 .. " is duplicated)", json.message)

        -- make sure we did not change certificates or snis
        local json = get_certificates()
        assert.same(json_before, json)
      end)

      it("returns a conflict when a pre-existing sni present in " ..
         "the request is associated with another certificate", function()
        local certificate = add_certificate()
        local certificate2, names2 = add_certificate()
        local json_before = get_certificates()

        local res = client:patch("/certificates/" .. certificate.id, {
          body    = {
            snis  = names2,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("schema violation (snis: " .. names2[1] .. " already associated with " ..
                      "existing certificate '" .. certificate2.id .. "')",
                      json.message)

        -- make sure we did not add any certificate or sni
        local json = get_certificates()
        assert.same(json_before, json)
      end)

      it("deletes all snis from a certificate if snis field is JSON null", function()
        -- Note: we currently do not support unsetting a field with
        -- form-urlencoded requests. This depends on upcoming work
        -- to the Admin API. We here follow the road taken by:
        -- https://github.com/Kong/kong/pull/2700
        local certificate = add_certificate()
        local json_before = get_certificates()

        local res = client:patch("/certificates/" .. certificate.id, {
          body    = {
            snis  = ngx.null,
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(0, #json.snis)
        assert.matches('"snis":[]', body, nil, true)

        -- make sure we did not add any certificate and the sni was deleted
        local json = get_certificates()
        assert.equal(#json_before.data, #json.data)
        for i, data in ipairs(json.data) do
          if data.id == certificate.id then
            assert.same({}, data.snis)
          else
            assert.same(json_before.data[i].snis, data.snis)
          end
        end
      end)
    end)

    describe("DELETE", function()
      it("deletes a certificate and all related snis", function()
        local json_before = get_certificates()
        local _, names = add_certificate()

        local res = client:delete("/certificates/" .. names[1])
        assert.res_status(204, res)

        local json = get_certificates()
        assert.same(json_before, json)
      end)

      it("deletes a certificate by id", function()
        local json_before = get_certificates()
        local certificate = add_certificate()

        local res = client:delete("/certificates/" .. certificate.id)
        assert.res_status(204, res)

        local json = get_certificates()
        assert.same(json_before, json)
      end)
    end)
  end)


  describe("/certificates/:certificate/snis", function()
    describe("POST", function()

      describe("errors", function()
        it("certificate doesn't exist", function()
          local res = client:post("/certificates/585e4c16-c656-11e6-8db9-5f512d8a12cd/snis", {
            body = {
              name = get_name(),
            },
            headers = { ["Content-Type"] = "application/json" },
          })

          local body = assert.res_status(404, res)
          local json = cjson.decode(body)
          assert.same("Not found", json.message)
        end)
      end)

      it_content_types("creates a sni using a certificate id", function(content_type)
        return function()
          local certificate = add_certificate()
          local n1 = get_name()
          local res = client:post("/certificates/" .. certificate.id .. "/snis", {
            body = {
              name = n1,
            },
            headers = { ["Content-Type"] = content_type },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal(n1, json.name)
          assert.equal(certificate.id, json.certificate.id)
        end
      end)

      it_content_types("creates a sni using a sni to id the certificate", function(content_type)
        return function()
          local certificate, names = add_certificate()
          local n1 = get_name()
          local res = client:post("/certificates/" .. names[1] .. "/snis", {
            body = {
              name = n1,
            },
            headers = { ["Content-Type"] = content_type },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal(n1, json.name)
          assert.equal(certificate.id, json.certificate.id)
        end
      end)

      it("returns a conflict when an sni already exists", function()
        local certificate, names = add_certificate()

        local res = client:post("/certificates/" .. certificate.id .. "/snis", {
          body    = {
            name = names[1],
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(409, res)
        local json = cjson.decode(body)
        assert.equals("unique constraint violation", json.name)
      end)
    end)

    describe("GET", function()
      it("retrieves a list of snis", function()
        local n1 = get_name()

        local certificate = bp.certificates:insert()
        bp.snis:insert {
          name        = n1,
          certificate = certificate,
        }

        local res  = client:get("/certificates/" .. certificate.id .. "/snis")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(1, #json.data)
        assert.equal(n1, json.data[1].name)
        assert.equal(certificate.id, json.data[1].certificate.id)
      end)
    end)
  end)

  describe("/snis/:name", function()

    describe("wildcard snis", function()

      describe("POST", function()
        it("creates with prefix wildcard", function()
          local certificate = add_certificate()
          local n1 = get_name()

          local res = client:post("/snis", {
            body = {
              name = "*." .. n1,
              certificate = { id = certificate.id },
            },
            headers = { ["Content-Type"] = "application/json" },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("*." .. n1, json.name)
          assert.equal(certificate.id, json.certificate.id)
        end)

        it("creates with suffix wildcard", function()
          local certificate = add_certificate()
          local n1 = get_name()

          local res = client:post("/snis", {
            body = {
              name = n1 .. ".*",
              certificate = { id = certificate.id },
            },
            headers = { ["Content-Type"] = "application/json" },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal(n1 .. ".*", json.name)
          assert.equal(certificate.id, json.certificate.id)
        end)

        it("rejects invalid SNIs", function()
          local certificate = add_certificate()

          local res = client:post("/snis", {
            body = {
              name = "*.wildcard.*",
              certificate = { id = certificate.id },
            },
            headers = { ["Content-Type"] = "application/json" },
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.equal("only one wildcard must be specified", json.fields.name)
        end)
      end)

      describe("GET", function()

        it("retrieves a wildcard SNI using the name", function()
          local certificate = add_certificate()

          bp.snis:insert({
            name = "*.wildcard.com",
            certificate = { id = certificate.id },
          })

          local res = client:get("/snis/%2A.wildcard.com")
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("*.wildcard.com", json.name)
        end)
      end)
    end)

    describe("GET", function()
      it("retrieves a sni using the name", function()
        local certificate, names = add_certificate()
        local res  = client:get("/snis/" .. names[1])
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(names[1], json.name)
        assert.equal(certificate.id, json.certificate.id)
      end)
      it("retrieves a sni using the id", function()
        local certificate = add_certificate()
        local n1 = get_name()
        local sni = bp.snis:insert({
          name = n1,
          certificate = { id = certificate.id },
        })

        local res  = client:get("/snis/" .. sni.id)
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(n1, json.name)
        assert.equal(certificate.id, json.certificate.id)
      end)
    end)

    describe("PUT", function()
      it("creates if not found", function()
        local certificate = add_certificate()
        local n1 = get_name()
        local id = utils.uuid()
        local res = client:put("/snis/" .. id, {
          body = {
            certificate = { id = certificate.id },
            name = n1,
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(n1, json.name)

        local in_db = assert(db.snis:select({ id = id }, { nulls = true }))
        assert.same(json, in_db)
      end)

      it("updates if found", function()
        local certificate = add_certificate()
        local n1 = get_name()
        local sni = bp.snis:insert({
          name = n1,
          certificate = { id = certificate.id },
        })
        local n2 = get_name()

        local res = client:put("/snis/" .. sni.id, {
          body = {
            name = n2,
            certificate = { id = certificate.id },
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(n2, json.name)

        local in_db = assert(db.snis:select({ id = sni.id }, { nulls = true }))
        assert.same(json, in_db)
      end)

      it("handles invalid input", function()
        -- Missing params
        local res = client:put("/snis/" .. utils.uuid(), {
          body = {},
          headers = { ["Content-Type"] = "application/json" }
        })
        local body = assert.res_status(400, res)
        assert.same({
          code     = Errors.codes.SCHEMA_VIOLATION,
          name     = "schema violation",
          message  = "2 schema violations (certificate: required field missing; name: required field missing)",
          fields   = {
            certificate = "required field missing",
            name = "required field missing",
          }
        }, cjson.decode(body))
      end)
    end)

    describe("PATCH", function()
      it("updates a sni", function()
        local certificate, names = add_certificate()

        local certificate_2 = bp.certificates:insert {
          cert = ssl_fixtures.cert_alt,
          key = ssl_fixtures.key_alt,
        }

        local res = client:patch("/snis/" .. names[1], {
          body = {
            certificate = { id = certificate_2.id },
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(certificate_2.id, json.certificate.id)

        local res = client:get("/certificates/" .. certificate.id)
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same({ names[2] }, json.snis)

        local res = client:get("/certificates/" .. certificate_2.id)
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same({ names[1] }, json.snis)
      end)
    end)

    describe("DELETE", function()
      it("deletes a sni", function()
        local certificate = add_certificate()
        local n1 = get_name()
        bp.snis:insert({
          name = n1,
          certificate = { id = certificate.id },
        })

        local res = client:delete("/snis/" .. n1)
        assert.res_status(204, res)
      end)
    end)
  end)
end)

end
