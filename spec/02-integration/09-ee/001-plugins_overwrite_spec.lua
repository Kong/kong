local helpers = require "spec.helpers"
local cjson = require "cjson"


describe("Plugins overwrite:", function()
  local _
  local bp
  local client

  describe("[key-auth]",function()
    describe("by default key_in_body",function()

      setup(function()
        assert(helpers.start_kong())
        client = helpers.admin_client()
        bp, _, _ = helpers.get_db_utils()
      end)

      teardown(helpers.stop_kong)

      it("has a default value of false",function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/key-auth",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.False(json.fields.key_in_body.default)
      end)
      it("has no overwrite value",function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/key-auth",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.fields.key_in_body.overwrite)
      end)
      it("is false by default",function()
        local route = assert(bp.routes:insert {
          hosts = { "keyauth1.test" },
        })
        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "key-auth",
            route_id = route.id,
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.False(json.config.key_in_body)
      end)
      it("can be set to true",function()
        local  route = assert(bp.routes:insert {
          hosts = { "keyauth2.test" },
        })
        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "key-auth",
            route_id = route.id,
            config = {
              key_in_body = true,
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.True(json.config.key_in_body)
      end)
    end)

    describe("with feature-flag 'key_auth_disable_key_in_body=on', key_in_body",function()

      setup(function()
        assert(helpers.start_kong{
          feature_conf_path = "spec/fixtures/ee/feature_key_auth.conf",
        })
        client = helpers.admin_client()
        bp, _, _ = helpers.get_db_utils()
      end)

      teardown(helpers.stop_kong)

      it("has no default value",function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/key-auth",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.fields.key_in_body.default)
      end)
      it("has an overwrite value of false",function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/key-auth",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.False(json.fields.key_in_body.overwrite)
      end)
      it("cannot be set to any value",function()
        local  route = assert(bp.routes:insert {
          hosts = { "keyauth1.test" },
        })

        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "key-auth",
            route_id = route.id,
            config = {
              key_in_body = false,
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
       local body = assert.res_status(400, res)
       local json = cjson.decode(body)
       assert.equal("key_in_body cannot be set in your environment",
                    json["config.key_in_body"])

        res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "key-auth",
            route_id = route.id,
            config = {
              key_in_body = true,
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
       local body = assert.res_status(400, res)
       local json = cjson.decode(body)
       assert.equal("key_in_body cannot be set in your environment",
                    json["config.key_in_body"])
      end)
      it("is set to false",function()
        local  route = assert(bp.routes:insert {
          hosts = { "keyauth2.test" },
        })

        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "key-auth",
            route_id = route.id,
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.False(json.config.key_in_body)
      end)
    end)
  end)

  describe("[hmac-auth]",function()
    describe("by default validate_request_body",function()

      setup(function()
        assert(helpers.start_kong())
        client = helpers.admin_client()
        bp, _, _ = helpers.get_db_utils()
      end)

      teardown(helpers.stop_kong)

      it("has a default value of false",function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/hmac-auth",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.False(json.fields.validate_request_body.default)
      end)
      it("has no overwrite value",function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/hmac-auth",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.fields.validate_request_body.overwrite)
      end)
      it("is false by default",function()
        local  route = assert(bp.routes:insert {
          hosts = { "hmacauth1.test" },
        })
        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "hmac-auth",
            route_id = route.id,
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.False(json.config.validate_request_body)
      end)
      it("can be set to true",function()
        local  route = assert(bp.routes:insert {
          hosts = { "hmacauth2.test" },
        })
        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "hmac-auth",
            route_id = route.id,
            config = {
              validate_request_body = true,
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.True(json.config.validate_request_body)
      end)
    end)

    describe("with feature-flag 'hmac_auth_disable_validate_request_body=on', validate_request_body",function()

      setup(function()
        assert(helpers.start_kong{
          feature_conf_path = "spec/fixtures/ee/feature_hmac_auth.conf",
        })
        client = helpers.admin_client()
        bp, _, _ = helpers.get_db_utils()
      end)

      teardown(helpers.stop_kong)

      it("has no default value",function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/hmac-auth",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.fields.validate_request_body.default)
      end)
      it("has an overwrite value of false",function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/hmac-auth",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.False(json.fields.validate_request_body.overwrite)
      end)
      it("cannot be set to any value",function()
        local  route = assert(bp.routes:insert {
          hosts = { "hmacauth1.test" },
        })

        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "hmac-auth",
            route_id = route.id,
            config = {
              validate_request_body = false,
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
       local body = assert.res_status(400, res)
       local json = cjson.decode(body)
       assert.equal("validate_request_body cannot be set in your environment",
                    json["config.validate_request_body"])

        res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "hmac-auth",
            route_id = route.id,
            config = {
              validate_request_body = true,
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
       local body = assert.res_status(400, res)
       local json = cjson.decode(body)
       assert.equal("validate_request_body cannot be set in your environment",
                    json["config.validate_request_body"])
      end)
      it("is set to false",function()
        local  route = assert(bp.routes:insert {
          hosts = { "hmacauth2.test" },
        })

        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "hmac-auth",
            route_id = route.id,
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.False(json.config.validate_request_body)
      end)
    end)
  end)
end)
