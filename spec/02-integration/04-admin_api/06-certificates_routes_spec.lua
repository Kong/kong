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


local function get_snis_lists(certs)
  local lists = {}
  for i=1, #certs do
    lists[i] = certs[i].snis
  end

  table.sort(lists, function(a,b)
    if not a[1] then
      return true
    end
    if not b[1] then
      return false
    end

    return a[1] < b[1]
  end)

  return lists
end


for _, strategy in helpers.each_strategy() do

describe("Admin API: #" .. strategy, function()
  local client

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
    bp, db = helpers.get_db_utils(strategy, {})

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

        assert(db:truncate("certificates"))
        assert(db:truncate("snis"))

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

        local res  = client:get("/certificates")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(1, #json.data)
        assert.is_string(json.data[1].cert)
        assert.is_string(json.data[1].key)
        assert.same(my_snis, json.data[1].snis)
      end)
    end)

    describe("POST", function()

      before_each(function()
        assert(db:truncate("certificates"))
        assert(db:truncate("snis"))

        local res = client:post("/certificates", {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { "foo.com", "bar.com" },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        assert.res_status(201, res)
      end)

      it("returns a conflict when duplicated snis are present in the request", function()
        local res = client:post("/certificates", {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { "foobar.com", "baz.com", "foobar.com" },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equals("schema violation (snis: foobar.com is duplicated)", json.message)

        -- make sure we didnt add the certificate, or any snis
        res  = client:get("/certificates")
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(1, #json.data)
        assert.same({ "bar.com", "foo.com" }, json.data[1].snis)
      end)

      it("returns a conflict when a pre-existing sni is detected", function()
        local res = client:post("/certificates", {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { "foo.com" },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.matches("snis: foo.com already associated with existing certificate", json.message)

        -- make sure we only have one certificate, with two snis
        res  = client:get("/certificates")
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(1, #json.data)
        assert.same({ "bar.com", "foo.com" }, json.data[1].snis)
      end)

      it_content_types("creates a certificate and returns it with the snis pseudo-property", function(content_type)
        return function()
          local body
          if content_type == "multipart/form-data" then
            body = {
              cert        = ssl_fixtures.cert,
              key         = ssl_fixtures.key,
              ["snis[1]"] = "foobar.com",
              ["snis[2]"] = "baz.com",
            }
          elseif content_type == "application/x-www-form-urlencoded" then
            body = {
              cert = require "socket.url".escape(ssl_fixtures.cert),
              key  = require "socket.url".escape(ssl_fixtures.key),
              snis = { "foobar.com", "baz.com", }
            }
          else
            body = {
              cert = ssl_fixtures.cert,
              key  = ssl_fixtures.key,
              snis = { "foobar.com", "baz.com", }
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
          assert.same({ "baz.com", "foobar.com" }, json.snis)
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
    local certificate

    before_each(function()
      assert(db:truncate("certificates"))
      assert(db:truncate("snis"))

      local res = client:post("/certificates", {
        body    = {
          cert  = ssl_fixtures.cert,
          key   = ssl_fixtures.key,
          snis  = { "foo.com", "bar.com" },
        },
        headers = { ["Content-Type"] = "application/json" },
      })

      local body = assert.res_status(201, res)
      certificate = cjson.decode(body)
    end)

    describe("GET", function()
      it("retrieves a certificate by id", function()
        local res1  = client:get("/certificates/" .. certificate.id)
        local body1 = assert.res_status(200, res1)
        local json1 = cjson.decode(body1)

        assert.is_string(json1.cert)
        assert.is_string(json1.key)
        assert.same({ "bar.com", "foo.com" }, json1.snis)
      end)

      it("retrieves a certificate by sni", function()
        local res1  = client:get("/certificates/foo.com")
        local body1 = assert.res_status(200, res1)
        local json1 = cjson.decode(body1)

        local res2  = client:get("/certificates/bar.com")
        local body2 = assert.res_status(200, res2)
        local json2 = cjson.decode(body2)

        assert.is_string(json1.cert)
        assert.is_string(json1.key)
        assert.same({ "bar.com", "foo.com" }, json1.snis)
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
        local id = utils.uuid()
        local res = client:put("/certificates/" .. id, {
          body = {
            cert = ssl_fixtures.cert,
            key = ssl_fixtures.key,
            snis = { "example.com" },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(ssl_fixtures.cert, json.cert)

        assert.same({ "example.com" }, json.snis)
        json.snis = nil

        local in_db = assert(db.certificates:select({ id = id }))
        assert.same(json, in_db)
      end)

      it("creates a new sni when provided in the url", function()
        local res = client:put("/certificates/new-sni.com", {
          body = {
            cert = ssl_fixtures.cert,
            key = ssl_fixtures.key,
            snis = { "example.com" },
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(ssl_fixtures.cert, json.cert)

        assert.same({ "example.com", "new-sni.com" }, json.snis)
        json.snis = nil

        local in_db = assert(db.certificates:select({ id = json.id }))
        assert.same(json, in_db)
      end)

      it("updates if found", function()
        local res = client:put("/certificates/" .. certificate.id, {
          body = { cert = ssl_fixtures.cert_alt, key = ssl_fixtures.key_alt },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(ssl_fixtures.cert_alt, json.cert)
        assert.same(ssl_fixtures.key_alt, json.key)
        assert.same({"bar.com", "foo.com"}, json.snis)

        json.snis = nil

        local in_db = assert(db.certificates:select({ id = certificate.id }))
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
      local cert_foo
      local cert_bar

      before_each(function()
        assert(db:truncate("certificates"))
        assert(db:truncate("snis"))

        local res = client:post("/certificates", {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { "foo.com" },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(201, res)
        cert_foo = cjson.decode(body)

        local res = client:post("/certificates", {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { "bar.com" },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(201, res)
        cert_bar = cjson.decode(body)
      end)

      it_content_types("updates a certificate by cert id", function(content_type)
        return function()
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

          local res = client:patch("/certificates/" .. cert_foo.id, {
            body = body,
            headers = { ["Content-Type"] = content_type }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(ssl_fixtures.cert_alt, json.cert)
        end
      end)

      it_content_types("updates a certificate by sni", function(content_type)
        return function()
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

          local res = client:patch("/certificates/foo.com", {
            body = body,
            headers = { ["Content-Type"] = content_type }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(ssl_fixtures.cert_alt, json.cert)
        end
      end)

      it("returns 404 for a random non-existing id", function()
        local res = client:patch("/certificates/" .. utils.uuid(), {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = { "baz.com" },
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        assert.res_status(404, res)

        -- make sure we did not add any certificate or sni
        res  = client:get("/certificates")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.same({ { "bar.com" }, { "foo.com" } }, get_snis_lists(json.data))
      end)

      it("updates snis associated with a certificate", function()
        local res = client:patch("/certificates/" .. cert_foo.id, {
          body    = { snis = { "baz.com" }, },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same({ "baz.com" }, json.snis)

        -- make sure we did not add any certificate, and that the snis
        -- are correct
        res  = client:get("/certificates")
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.same({ { "bar.com" }, { "baz.com" } }, get_snis_lists(json.data))
      end)

      it("updates only the certificate if no snis are specified", function()
        local res = client:patch( "/certificates/" .. cert_bar.id, {
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- make sure certificate got updated and sni remains the same
        assert.same({ "bar.com" }, json.snis)
        assert.same(ssl_fixtures.cert, json.cert)
        assert.same(ssl_fixtures.key, json.key)

        -- make sure the certificate got updated in DB
        res  = client:get("/certificates/" .. cert_bar.id)
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(ssl_fixtures.cert, json.cert)
        assert.equal(ssl_fixtures.key, json.key)

        -- make sure we did not add any certificate or sni
        res  = client:get("/certificates")
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.same({ { "bar.com" }, { "foo.com" } }, get_snis_lists(json.data))
      end)

      it("returns a conflict when duplicated snis are present in the request", function()
        local res = client:patch("/certificates/" .. cert_bar.id, {
          body    = {
            snis  = { "baz.com", "baz.com" },
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("schema violation (snis: baz.com is duplicated)", json.message)

        -- make sure we did not change certificates or snis
        res = client:get("/certificates")
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.same({ { "bar.com" }, { "foo.com" } }, get_snis_lists(json.data))
      end)

      it("returns a conflict when a pre-existing sni present in " ..
         "the request is associated with another certificate", function()
        local res = client:patch("/certificates/" .. cert_bar.id, {
          body    = {
            snis  = { "foo.com", "baz.com" },
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("schema violation (snis: foo.com already associated with " ..
                      "existing certificate '" .. cert_foo.id .. "')",
                      json.message)

        -- make sure we did not add any certificate or sni
        res  = client:get("/certificates")
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.same({ { "bar.com" }, { "foo.com" } }, get_snis_lists(json.data))
      end)

      it("deletes all snis from a certificate if snis field is JSON null", function()
        -- Note: we currently do not support unsetting a field with
        -- form-urlencoded requests. This depends on upcoming work
        -- to the Admin API. We here follow the road taken by:
        -- https://github.com/Kong/kong/pull/2700
        local res = client:patch("/certificates/" .. cert_bar.id, {
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
        res  = client:get("/certificates")
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.same({ {}, { "foo.com" } }, get_snis_lists(json.data))
      end)
    end)

    describe("DELETE", function()
      it("deletes a certificate and all related snis", function()
        local res = client:delete("/certificates/foo.com")
        assert.res_status(204, res)

        res = client:get("/certificates")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(0, #json.data)
      end)

      it("deletes a certificate by id", function()
        local res = client:post("/certificates", {
          body = {
            cert = ssl_fixtures.cert,
            key = ssl_fixtures.key,
          },
          headers = { ["Content-Type"] = "application/json" }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        local res = client:delete("/certificates/" .. json.id)
        assert.res_status(204, res)

        res = client:get("/certificates")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(1, #json.data)
      end)
    end)
  end)


  describe("/certificates/:certificate/snis", function()
    describe("POST", function()

      local certificate
      before_each(function()
        assert(db:truncate("certificates"))
        assert(db:truncate("snis"))

        certificate = bp.certificates:insert()
        bp.snis:insert({
          name = "ttt.com",
          certificate = { id = certificate.id }
        })
      end)

      describe("errors", function()
        it("certificate doesn't exist", function()
          local res = client:post("/certificates/585e4c16-c656-11e6-8db9-5f512d8a12cd/snis", {
            body = {
              name = "bar.com",
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
          local res = client:post("/certificates/" .. certificate.id .. "/snis", {
            body = {
              name = "foo.com",
            },
            headers = { ["Content-Type"] = content_type },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("foo.com", json.name)
          assert.equal(certificate.id, json.certificate.id)
        end
      end)

      it_content_types("creates a sni using a sni to id the certificate", function(content_type)
        return function()
          local res = client:post("/certificates/ttt.com/snis", {
            body = {
              name = "foo.com",
            },
            headers = { ["Content-Type"] = content_type },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("foo.com", json.name)
          assert.equal(certificate.id, json.certificate.id)
        end
      end)

      it("returns a conflict when an sni already exists", function()
        bp.snis:insert {
          name = "foo.com",
          certificate = certificate,
        }

        local res = client:post("/certificates/" .. certificate.id .. "/snis", {
          body    = {
            name = "foo.com",
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
        assert(db:truncate("certificates"))
        assert(db:truncate("snis"))

        local certificate = bp.certificates:insert()
        bp.snis:insert {
          name        = "foo.com",
          certificate = certificate,
        }

        local res  = client:get("/certificates/" .. certificate.id .. "/snis")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(1, #json.data)
        assert.equal("foo.com", json.data[1].name)
        assert.equal(certificate.id, json.data[1].certificate.id)
      end)
    end)
  end)

  describe("/snis/:name", function()
    local certificate, sni

    before_each(function()
      assert(db:truncate("certificates"))
      assert(db:truncate("snis"))

      certificate = bp.certificates:insert()
      sni = bp.snis:insert {
        name        = "foo.com",
        certificate = certificate,
      }
    end)

    describe("GET", function()
      it("retrieves a sni using the name", function()
        local res  = client:get("/snis/foo.com")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("foo.com", json.name)
        assert.equal(certificate.id, json.certificate.id)
      end)
      it("retrieves a sni using the id", function()
        local res  = client:get("/snis/" .. sni.id)
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("foo.com", json.name)
        assert.equal(certificate.id, json.certificate.id)
      end)
    end)

    describe("PUT", function()
      it("creates if not found", function()
        local id = utils.uuid()
        local res = client:put("/snis/" .. id, {
          body = {
            certificate = { id = certificate.id },
            name = "created.com",
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same("created.com", json.name)

        local in_db = assert(db.snis:select({ id = id }))
        assert.same(json, in_db)
      end)

      it("updates if found", function()
        local res = client:put("/snis/" .. sni.id, {
          body = {
            name = "updated.com",
            certificate = { id = certificate.id },
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same("updated.com", json.name)

        local in_db = assert(db.snis:select({ id = sni.id }))
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
        local certificate_2 = bp.certificates:insert {
          cert = ssl_fixtures.cert_alt,
          key = ssl_fixtures.key_alt,
        }

        local res = client:patch("/snis/foo.com", {
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
        assert.same({}, json.snis)

        local res = client:get("/certificates/" .. certificate_2.id)
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same({ "foo.com" }, json.snis)
      end)
    end)

    describe("DELETE", function()
      it("deletes a sni", function()
        local res = client:delete("/snis/foo.com")
        assert.res_status(204, res)
      end)
    end)
  end)
end)

end
