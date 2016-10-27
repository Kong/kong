local ssl_fixtures = require "spec.03-plugins.16-ssl.fixtures"
local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: basic-auth (API)", function()
  local admin_client
  setup(function()
    assert(helpers.start_kong())
    admin_client = helpers.admin_client()
  end)
  teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("/apis/:api/plugins/", function()
    setup(function()
      assert(helpers.dao.apis:insert {
        request_host = "mockbin.com",
        upstream_url = "http://mockbin.com"
      })
    end)
    after_each(function()
      helpers.dao:truncate_table("plugins")
    end)

    describe("POST", function()
      it("creates a new ssl plugin", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/apis/mockbin.com/plugins",
          body = {
            name = "ssl",
            ["config.cert"] = ssl_fixtures.cert,
            ["config.key"] = ssl_fixtures.key
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal(ssl_fixtures.cert, json.config.cert)
        assert.equal(ssl_fixtures.key, json.config.key)
      end)
      describe("errors", function()
        it("should not convert an invalid cert to DER", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/apis/mockbin.com/plugins",
            body = {
              name = "ssl",
              ["config.cert"] = "asd",
              ["config.key"] = ssl_fixtures.key
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"config.cert":"Invalid SSL certificate"}]], body)
        end)
        it("should not convert an invalid key to DER", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/apis/mockbin.com/plugins",
            body = {
              name = "ssl",
              ["config.cert"] = ssl_fixtures.cert,
              ["config.key"] = "hello"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"config.key":"Invalid SSL certificate key"}]], body)
        end)
        it("returns bad request", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/apis/mockbin.com/plugins",
            body = {
              name = "ssl",
              consumer_id = "504b535e-dc1c-11e5-8554-b3852c1ec156",
              ["config.cert"] = ssl_fixtures.cert,
              ["config.key"] = ssl_fixtures.key
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"message":"No consumer can be configured for that plugin"}]], body)
        end)
      end)
    end)
  end)
end)
