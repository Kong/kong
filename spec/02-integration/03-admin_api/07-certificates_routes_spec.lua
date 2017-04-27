local ssl_fixtures = require "spec.fixtures.ssl"
local dao_helpers = require "spec.02-integration.02-dao.helpers"
local DAOFactory = require "kong.dao.factory"
local helpers = require "spec.helpers"
local cjson = require "cjson"


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title.." with application/www-form-urlencoded", test_form_encoded)
  it(title.." with application/json", test_json)
end


dao_helpers.for_each_dao(function(kong_config)

describe("Admin API", function()
  local client
  local dao

  setup(function()
    dao = assert(DAOFactory.new(kong_config))

    assert(helpers.start_kong({
      database = kong_config.database
    }))

    client = assert(helpers.admin_client())
  end)

  teardown(function()
    if client then
      client:close()
    end

    helpers.stop_kong()
  end)

  describe("/certificates with " .. kong_config.database, function()

    describe("POST", function()
      before_each(function()
        dao:truncate_tables()
      end)

      it("returns a conflict when duplicates snis are present in the request", function()
        local res = assert(client:send {
          method  = "POST",
          path    = "/certificates",
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = "foo.com,bar.com,foo.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(409, res)
        local json = cjson.decode(body)
        assert.equals('duplicate requested sni name foo.com', json.message)

        -- make sure we dont add any snis
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(0, #json.data)
        assert.equal(0, json.total)

        -- make sure we didnt add the certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(0, #json)
      end)

      it("returns a conflict when a pre-existing sni is detected", function()
        local res = assert(client:send {
          method  = "POST",
          path    = "/certificates",
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = "foo.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        assert.res_status(201, res)

        res = assert(client:send {
          method  = "POST",
          path    = "/certificates",
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = "foo.com,bar.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(409, res)
        local json = cjson.decode(body)
        assert.equals("entry already exists with name foo.com", json.message)

        -- make sure we only have one sni
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(1, #json.data)
        assert.equal(1, json.total)
        assert.equal("foo.com", json.data[1].name)

        -- make sure we only have one certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(1, json.total)
        assert.equal(1, #json.data)
        assert.is_string(json.data[1].cert)
        assert.is_string(json.data[1].key)
        assert.same({ "foo.com" }, json.data[1].snis)
      end)

      it_content_types("creates a certificate", function(content_type)
        return function()
          local res = assert(client:send {
            method  = "POST",
            path    = "/certificates",
            body    = {
              cert  = ssl_fixtures.cert,
              key   = ssl_fixtures.key,
              snis  = "foo.com,bar.com",
            },
            headers = { ["Content-Type"] = content_type },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.is_string(json.cert)
          assert.is_string(json.key)
          assert.same({ "foo.com", "bar.com" }, json.snis)
        end
      end)
    end)

    describe("GET", function()
      it("retrieves all certificates", function()
        local res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(1, json.total)
        assert.equal(1, #json.data)
        assert.is_string(json.data[1].cert)
        assert.is_string(json.data[1].key)
        assert.same({ "foo.com", "bar.com" }, json.data[1].snis)
      end)
    end)
  end)

  describe("/certificates/:sni_or_uuid", function()

    describe("GET", function()
      it("retrieves a certificate by SNI", function()
        local res1 = assert(client:send {
          method   = "GET",
          path     = "/certificates/foo.com",
        })

        local body1 = assert.res_status(200, res1)
        local json1 = cjson.decode(body1)

        local res2 = assert(client:send {
          method   = "GET",
          path     = "/certificates/bar.com",
        })

        local body2 = assert.res_status(200, res2)
        local json2 = cjson.decode(body2)

        assert.is_string(json1.cert)
        assert.is_string(json1.key)
        assert.same({ "foo.com", "bar.com" }, json1.snis)
        assert.same(json1, json2)
      end)
    end)

    describe("PATCH", function()
      it_content_types("updates a certificate by SNI", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/certificates/foo.com",
            body = {
              cert = content_type
            },
            headers = { ["Content-Type"] = content_type }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(content_type, json.cert)
        end
      end)
    end)

    describe("DELETE", function()
      it("deletes a certificate and all related SNIs", function()
        local res = assert(client:send {
          method  = "DELETE",
          path    = "/certificates/foo.com",
        })

        assert.res_status(204, res)

        res = assert(client:send {
          method = "GET",
          path = "/certificates/foo.com",
        })

        assert.res_status(404, res)

        res = assert(client:send {
          method = "GET",
          path = "/certificates/bar.com",
        })

        assert.res_status(404, res)
      end)

      it("deletes a certificate by id", function()
        local res = assert(client:send {
          method = "POST",
          path = "/certificates",
          body = {
            cert = "foo",
            key = "bar",
          },
          headers = { ["Content-Type"] = "application/json" }
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        res = assert(client:send {
          method = "DELETE",
          path = "/certificates/" .. json.id,
        })

        assert.res_status(204, res)
      end)
    end)
  end)


  describe("/snis with " .. kong_config.database, function()
    local ssl_certificate

    describe("POST", function()
      before_each(function()
        dao:truncate_tables()

        ssl_certificate = assert(dao.ssl_certificates:insert {
          cert = ssl_fixtures.cert,
          key = ssl_fixtures.key,
        })
      end)

      describe("errors", function()
        it("certificate doesn't exist", function()
          local res = assert(client:send {
            method = "POST",
            path   = "/snis",
            body   = {
              name               = "bar.com",
              ssl_certificate_id = "585e4c16-c656-11e6-8db9-5f512d8a12cd",
            },
            headers = { ["Content-Type"] = "application/json" },
          })

          local body = assert.res_status(404, res)
          local json = cjson.decode(body)
          assert.same({ ssl_certificate_id = "does not exist with value "
                    .. "'585e4c16-c656-11e6-8db9-5f512d8a12cd'" }, json)
        end)
      end)

      it_content_types("creates a SNI", function(content_type)
        return function()
          local res = assert(client:send {
            method  = "POST",
            path    = "/snis",
            body    = {
              name               = "foo.com",
              ssl_certificate_id = ssl_certificate.id,
            },
            headers = { ["Content-Type"] = content_type },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("foo.com", json.name)
          assert.equal(ssl_certificate.id, json.ssl_certificate_id)
        end
      end)

      it("returns a conflict when an SNI already exists", function()
          assert(dao.ssl_servers_names:insert {
            name = "foo.com",
            ssl_certificate_id = ssl_certificate.id,
          })

          local res = assert(client:send {
            method  = "POST",
            path    = "/snis",
            body    = {
              name               = "foo.com",
              ssl_certificate_id = ssl_certificate.id,
            },
            headers = { ["Content-Type"] = "application/json" },
          })

          local body = assert.res_status(409, res)
          local json = cjson.decode(body)
          assert.equals("already exists with value 'foo.com'", json.name)
      end)
    end)

    describe("GET", function()
      it("retrieves a SNI", function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(1, #json.data)
        assert.equal(1, json.total)
        assert.equal("foo.com", json.data[1].name)
        assert.equal(ssl_certificate.id, json.data[1].ssl_certificate_id)
      end)
    end)

    describe("/snis/:name", function()

      describe("GET", function()
        it("retrieves a SNI", function()
          local res = assert(client:send {
            mathod  = "GET",
            path    = "/snis/foo.com",
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("foo.com", json.name)
          assert.equal(ssl_certificate.id, json.ssl_certificate_id)
        end)
      end)

      describe("PATCH", function()
        local ssl_certificate_2

        setup(function()
          ssl_certificate_2 = assert(dao.ssl_certificates:insert {
            cert = "foo",
            key = "bar",
          })
        end)

        do
          local test = it
          if kong_config.database == "cassandra" then
            test = pending
          end

          test("updates a SNI", function()
            -- SKIP: this test fails with Cassandra because the PRIMARY KEY
            -- used by the C* table is a composite of (name,
            -- ssl_certificate_id), and hence, we cannot update the
            -- ssl_certificate_id field because it is in the `SET` part of the
            -- query built by the DAO, but in C*, one cannot change a value
            -- from the clustering key.
            local res = assert(client:send {
              method  = "PATCH",
              path    = "/snis/foo.com",
              body    = {
                ssl_certificate_id = ssl_certificate_2.id,
              },
              headers = { ["Content-Type"] = "application/json" },
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(ssl_certificate_2.id, json.ssl_certificate_id)
          end)
        end
      end)

      describe("DELETE", function()
        it("deletes a SNI", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/snis/foo.com",
          })

          assert.res_status(204, res)
        end)
      end)
    end)
  end)
end)

end)
