local ssl_fixtures = require "spec.fixtures.ssl"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local DAOFactory = require "kong.dao.factory"
local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local singletons = require "kong.singletons"


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with application/json", test_json)
end


dao_helpers.for_each_dao(function(kong_config)

describe("Admin API: #" .. kong_config.database, function()
  local client
  local dao

  before_each(function()
    client = assert(helpers.admin_client())
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  setup(function()
    dao = assert(DAOFactory.new(kong_config))
    assert(dao:run_migrations())

    singletons.dao = dao

    assert(helpers.start_kong({
      database = kong_config.database
    }))
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  describe("/certificates", function()
    before_each(function()
      dao:truncate_tables()
      local res = assert(client:send {
        method  = "POST",
        path    = "/certificates",
        body    = {
          cert  = ssl_fixtures.cert,
          key   = ssl_fixtures.key,
          snis  = "foo.com,bar.com",
        },
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      })

      assert.res_status(201, res)
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
        assert.contains("foo.com", json.data[1].snis)
        assert.contains("bar.com", json.data[1].snis)
      end)
    end)

    describe("POST", function()
      it("returns a conflict when duplicates snis are present in the request#t", function()
        local res = assert(client:send {
          method  = "POST",
          path    = "/certificates",
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = "foobar.com,baz.com,foobar.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(409, res)
        local json = cjson.decode(body)
        assert.equals("duplicate SNI in request: foobar.com", json.message)

        -- make sure we dont add any snis
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we didnt add the certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(1, #json.data)
        assert.equal(1, json.total)
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

        local body = assert.res_status(409, res)
        local json = cjson.decode(body)
        assert.equals("SNI already exists: foo.com", json.message)

        -- make sure we only have two snis
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)
        local sni_names = {}
        table.insert(sni_names, json.data[1].name)
        table.insert(sni_names, json.data[2].name)
        assert.contains("foo.com", sni_names)
        assert.contains("bar.com", sni_names)

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
        assert.contains("bar.com", json.data[1].snis)
        assert.contains("foo.com", json.data[1].snis)
      end)

      it_content_types("creates a certificate", function(content_type)
        return function()
          local res = assert(client:send {
            method  = "POST",
            path    = "/certificates",
            body    = {
              cert  = ssl_fixtures.cert,
              key   = ssl_fixtures.key,
              snis  = "foobar.com,baz.com",
            },
            headers = { ["Content-Type"] = content_type },
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.is_string(json.cert)
          assert.is_string(json.key)
          assert.same({ "foobar.com", "baz.com" }, json.snis)
        end
      end)

      it_content_types("returns snis as [] when none is set", function(content_type)
        return function()
          local res = assert(client:send {
            method  = "POST",
            path    = "/certificates",
            body    = {
              cert  = ssl_fixtures.cert,
              key   = ssl_fixtures.key,
            },
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

    describe("PUT", function()
      local cert_foo
      local cert_bar

      before_each(function()
        dao:truncate_tables()

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
        local body = assert.res_status(201, res)
        cert_foo = cjson.decode(body)

        local res = assert(client:send {
          method  = "POST",
          path    = "/certificates",
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = "bar.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })
        local body = assert.res_status(201, res)
        cert_bar = cjson.decode(body)
      end)

      it("creates a certificate if ID is not present in the body", function()
        local res = assert(client:send {
          method  = "PUT",
          path    = "/certificates",
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = "baz.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.is_string(json.cert)
        assert.is_string(json.key)
        assert.same({ "baz.com" }, json.snis)

        -- make sure we added an sni
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(3, #json.data)
        assert.equal(3, json.total)

        -- make sure we added our certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(3, #json.data)
        assert.equal(3, json.total)
      end)

      it("returns 404 for a random non-existing id", function()
        local res = assert(client:send {
          method  = "PUT",
          path    = "/certificates",
          body    = {
            id = utils.uuid(),
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = "baz.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        assert.res_status(404, res)

        -- make sure we did not add any sni
        res = assert(client:send {
          method = "GET",
          path   = "/snis",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("returns Bad Request if only certificate is specified", function()
        local res = assert(client:send {
          method  = "PUT",
          path    = "/certificates",
          body    = {
            id = cert_foo.id,
            cert  = "cert_foo",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equals("key is required", json.key)

        -- make sure we did not add any sni
        res = assert(client:send {
          method = "GET",
          path   = "/snis",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("returns Bad Request if only key is specified", function()
        local res = assert(client:send {
          method  = "PUT",
          path    = "/certificates",
          body    = {
            id = cert_foo.id,
            key  = "key_foo",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equals("cert is required", json.cert)

        -- make sure we did not add any sni
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("updates snis associated with a certificate", function()
        local res = assert(client:send {
          method  = "PUT",
          path    = "/certificates",
          body    = {
            id = cert_foo.id,
            snis  = "baz.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same({ "baz.com" }, json.snis)

        -- make sure number of snis don't change
        -- since we delete foo.com and added baz.com
        res = assert(client:send {
          method = "GET",
          path   = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)
        local sni_names = {}
        table.insert(sni_names, json.data[1].name)
        table.insert(sni_names, json.data[2].name)
        assert.contains("baz.com", sni_names)
        assert.contains("bar.com", sni_names)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("updates only the certificate if no snis are specified", function()
        local res = assert(client:send {
          method  = "PUT",
          path    = "/certificates",
          body    = {
            id = cert_bar.id,
            cert  = "bar_cert",
            key   = "bar_key",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- make sure certificate got updated and sni remains the same
        assert.same({ "bar.com" }, json.snis)
        assert.same("bar_cert", json.cert)
        assert.same("bar_key", json.key)

        -- make sure the certificate got updated in DB
        res = assert(client:send {
          method = "GET",
          path = "/certificates/" .. cert_bar.id,
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal("bar_cert", json.cert)
        assert.equal("bar_key", json.key)

        -- make sure number of snis don't change
        res = assert(client:send {
          method = "GET",
          path   = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("returns a conflict when duplicates snis are present in the request", function()
        local res = assert(client:send {
          method  = "PUT",
          path    = "/certificates",
          body    = {
            id = cert_bar.id,
            snis  = "baz.com,baz.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(409, res)
        local json = cjson.decode(body)

        assert.equals("duplicate SNI in request: baz.com", json.message)

        -- make sure number of snis don't change
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("returns a conflict when a pre-existing sni present in " ..
         "the request is associated with another certificate", function()
        local res = assert(client:send {
          method  = "PUT",
          path    = "/certificates",
          body    = {
            id = cert_bar.id,
            snis  = "foo.com,baz.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(409, res)
        local json = cjson.decode(body)

        assert.equals("SNI 'foo.com' already associated with " ..
                      "existing certificate (" .. cert_foo.id .. ")",
                      json.message)

        -- make sure number of snis don't change
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("deletes all snis from a certificate if snis field is JSON null", function()
        -- Note: we currently do not support unsetting a field with
        -- form-urlencoded requests. This depends on upcoming work
        -- to the Admin API. We here follow the road taken by:
        -- https://github.com/Kong/kong/pull/2700
        local res = assert(client:send {
          method  = "PUT",
          path    = "/certificates",
          body    = {
            snis = ngx.null,
            id = cert_bar.id,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(0, #json.snis)
        assert.matches('"snis":[]', body, nil, true)

        -- make sure the sni was deleted
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(1, #json.data)
        assert.equal(1, json.total)
        assert.equal("foo.com", json.data[1].name)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)
    end)
  end)

  describe("/certificates/:sni_or_uuid", function()
    before_each(function()
      dao:truncate_tables()
      local res = assert(client:send {
        method  = "POST",
        path    = "/certificates",
        body    = {
          cert  = ssl_fixtures.cert,
          key   = ssl_fixtures.key,
          snis  = "foo.com,bar.com",
        },
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      })

      assert.res_status(201, res)
    end)

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
        assert.contains("foo.com", json1.snis)
        assert.contains("bar.com", json1.snis)
        assert.same(json1, json2)
      end)

      it("returns 404 for a random non-existing uuid", function()
        local res = assert(client:send {
          method = "GET",
          path = "/certificates/" .. utils.uuid(),
        })
        assert.res_status(404, res)
      end)

      it("returns 404 for a random non-existing SNI", function()
        local res = assert(client:send {
          method = "GET",
          path = "/certificates/doesntexist.com",
        })
        assert.res_status(404, res)
      end)
    end)

    describe("PATCH", function()
      local cert_foo
      local cert_bar

      before_each(function()
        dao:truncate_tables()

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
        local body = assert.res_status(201, res)
        cert_foo = cjson.decode(body)

        local res = assert(client:send {
          method  = "POST",
          path    = "/certificates",
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = "bar.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })
        local body = assert.res_status(201, res)
        cert_bar = cjson.decode(body)
      end)

      it_content_types("updates a certificate by SNI", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/certificates/foo.com",
            body = {
              cert = "foo_cert",
              key = "foo_key",
            },
            headers = { ["Content-Type"] = content_type }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal("foo_cert", json.cert)
        end
      end)

      it("returns 404 for a random non-existing id", function()
        local res = assert(client:send {
          method  = "PATCH",
          path    = "/certificates/" .. utils.uuid(),
          body    = {
            cert  = ssl_fixtures.cert,
            key   = ssl_fixtures.key,
            snis  = "baz.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        assert.res_status(404, res)

        -- make sure we did not add any sni
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("returns Bad Request if only certificate is specified", function()
        local res = assert(client:send {
          method  = "PATCH",
          path    = "/certificates/" .. cert_foo.id,
          body    = {
            cert  = "cert_foo",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equals("key is required", json.key)

        -- make sure we did not add any sni
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("returns Bad Request if only key is specified", function()
        local res = assert(client:send {
          method  = "PATCH",
          path    = "/certificates/" .. cert_foo.id,
          body    = {
            key  = "key_foo",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equals("cert is required", json.cert)

        -- make sure we did not add any sni
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("updates snis associated with a certificate", function()
        local res = assert(client:send {
          method  = "PATCH",
          path    = "/certificates/" .. cert_foo.id,
          body    = {
            snis  = "baz.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same({ "baz.com" }, json.snis)

        -- make sure number of snis don't change
        -- since we delete foo.com and added baz.com
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)
        local sni_names = {}
        table.insert(sni_names, json.data[1].name)
        table.insert(sni_names, json.data[2].name)
        assert.contains("baz.com", sni_names)
        assert.contains("bar.com", sni_names)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("updates only the certificate if no snis are specified", function()
        local res = assert(client:send {
          method  = "PATCH",
          path    = "/certificates/" .. cert_bar.id,
          body    = {
            cert  = "bar_cert",
            key   = "bar_key",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- make sure certificate got updated and sni remains the same
        assert.same({ "bar.com" }, json.snis)
        assert.same("bar_cert", json.cert)
        assert.same("bar_key", json.key)

        -- make sure the certificate got updated in DB
        res = assert(client:send {
          method = "GET",
          path = "/certificates/" .. cert_bar.id,
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal("bar_cert", json.cert)
        assert.equal("bar_key", json.key)

        -- make sure number of snis don't change
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("returns a conflict when duplicates snis are present in the request", function()
        local res = assert(client:send {
          method  = "PATCH",
          path    = "/certificates/" .. cert_bar.id,
          body    = {
            snis  = "baz.com,baz.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(409, res)
        local json = cjson.decode(body)

        assert.equals("duplicate SNI in request: baz.com", json.message)

        -- make sure number of snis don't change
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("returns a conflict when a pre-existing sni present in " ..
         "the request is associated with another certificate", function()
        local res = assert(client:send {
          method  = "PATCH",
          path    = "/certificates/" .. cert_bar.id,
          body    = {
            snis  = "foo.com,baz.com",
          },
          headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        })

        local body = assert.res_status(409, res)
        local json = cjson.decode(body)

        assert.equals("SNI 'foo.com' already associated with " ..
                      "existing certificate (" .. cert_foo.id .. ")",
                      json.message)

        -- make sure number of snis don't change
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
      end)

      it("deletes all snis from a certificate if snis field is JSON null", function()
        -- Note: we currently do not support unsetting a field with
        -- form-urlencoded requests. This depends on upcoming work
        -- to the Admin API. We here follow the road taken by:
        -- https://github.com/Kong/kong/pull/2700
        local res = assert(client:send {
          method  = "PATCH",
          path    = "/certificates/" .. cert_bar.id,
          body    = {
            snis  = ngx.null,
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(0, #json.snis)
        assert.matches('"snis":[]', body, nil, true)

        -- make sure the sni was deleted
        res = assert(client:send {
          method  = "GET",
          path    = "/snis",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(1, #json.data)
        assert.equal(1, json.total)
        assert.equal("foo.com", json.data[1].name)

        -- make sure we did not add any certificate
        res = assert(client:send {
          method = "GET",
          path = "/certificates",
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)
        assert.equal(2, json.total)
        assert.equal(2, #json.data)
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


  describe("/snis", function()
    local ssl_certificate

    before_each(function()
      dao:truncate_tables()
      ssl_certificate = dao.ssl_certificates:run_with_ws_scope(
        dao.workspaces:find_all({name = "default"}),
        dao.ssl_certificates.insert, {
          cert = ssl_fixtures.cert,
          key = ssl_fixtures.key,
      })

      assert(dao.ssl_servers_names:run_with_ws_scope(
               dao.workspaces:find_all({name = "default"}),
               dao.ssl_servers_names.insert, {
                 name               = "foo.com",
                 ssl_certificate_id = ssl_certificate.id,
      }))
    end)

    describe("POST", function()
      before_each(function()
        dao:truncate_tables()
        ssl_certificate = dao.ssl_certificates:run_with_ws_scope(
          dao.workspaces:find_all({name = "default"}),
          dao.ssl_certificates.insert, {
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
        assert(dao.ssl_servers_names:run_with_ws_scope(
                 dao.workspaces:find_all({name = "default"}),
                 dao.ssl_servers_names.insert, {
                   name               = "foo.com",
                   ssl_certificate_id = ssl_certificate.id,
        }))

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
  end)

  describe("/snis/:name", function()
    local ssl_certificate

    before_each(function()
      dao:truncate_tables()
      ssl_certificate = assert(dao.ssl_certificates:run_with_ws_scope(
                                 dao.workspaces:find_all({name = "default"}),
                                 dao.ssl_certificates.insert, {
                                   cert = ssl_fixtures.cert,
                                   key = ssl_fixtures.key,
      }))

      assert(dao.ssl_servers_names:run_with_ws_scope(
               dao.workspaces:find_all({name = "default"}),
               dao.ssl_servers_names.insert, {
                 name = "foo.com",
                 ssl_certificate_id = ssl_certificate.id,
      }))
    end)

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

          local ssl_certificate_2 = dao.ssl_certificates:run_with_ws_scope(
            dao.workspaces:find_all({name = "default"}), dao.ssl_certificates.insert, {
              cert = "foo",
              key = "bar",
          })

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

    describe("certificates through sni name", function()
      it("get a certificate if sni not exist", function()
        local res = assert(client:send {
          method = "GET",
          path = "/certificates/non-existent.com",
        })

        assert.res_status(404, res)
      end)
      it("patch a certificate if sni not exist", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/certificates/non-existent.com",
        })

        assert.res_status(404, res)
      end)
      it("delete a certificate if sni not exist", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/certificates/non-existent.com",
        })

        assert.res_status(404, res)
      end)
    end)
  end)
end)

end)
