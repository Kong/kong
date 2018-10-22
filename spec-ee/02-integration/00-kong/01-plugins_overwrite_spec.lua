local helpers = require "spec.helpers"
local cjson = require "cjson"


describe("Plugins overwrite:", function()
  local bp
  local client

  describe("[rate-limiting]", function()
    describe("with defaults", function()

      setup(function()
        assert(helpers.start_kong())
        client = helpers.admin_client()
        bp = helpers.get_db_utils()
      end)

      teardown(helpers.stop_kong)

      it("fields have correct defaults", function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/rate-limiting",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same("cluster", json.fields.policy.default)
        assert.is_nil(json.fields.redis_host.default)
        assert.same(6379, json.fields.redis_port.default)
        assert.same(0, json.fields.redis_database.default)
        assert.same(2000, json.fields.redis_timeout.default)
        assert.is_nil(json.fields.redis_password.default)
      end)
      it("fields have no overwrite", function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/rate-limiting",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.fields.policy.overwrite)
        assert.is_nil(json.fields.redis_host.overwrite)
        assert.is_nil(json.fields.redis_port.overwrite)
        assert.is_nil(json.fields.redis_password.overwrite)
        assert.is_nil(json.fields.redis_database.overwrite)
        assert.is_nil(json.fields.redis_timeout.overwrite)
      end)
      it("policy and redis fields can be set to a value", function()
        local route = assert(bp.routes:insert {
          hosts = { "rate-limit1.test" },
        })
        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "rate-limiting",
            route_id = route.id,
            config = {
              policy = "local",
              redis_host = "my-redis-host.net",
              redis_port = 4242,
              redis_timeout = 120,
              redis_database = 3,
              redis_password = "password",
              second = 1,
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal("local", json.config.policy)
        assert.equal("my-redis-host.net", json.config.redis_host)
        assert.equal(4242, json.config.redis_port)
        assert.equal(120, json.config.redis_timeout)
        assert.equal(3, json.config.redis_database)
        assert.equal("password", json.config.redis_password)
      end)
    end)

    describe("with feature-flag 'rate_limiting_restrict_redis_only=on',", function()

      setup(function()
        assert(helpers.start_kong{
          feature_conf_path = "spec-ee/fixtures/feature_rate_limit_plugins.conf",
        })
        client = helpers.admin_client()
        bp = helpers.get_db_utils()
      end)

      teardown(helpers.stop_kong)

      it("fields have no defaults", function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/rate-limiting",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.fields.policy.default)
        assert.is_nil(json.fields.redis_host.default)
        assert.is_nil(json.fields.redis_port.default)
        assert.is_nil(json.fields.redis_password.default)
        assert.is_nil(json.fields.redis_database.default)
        assert.is_nil(json.fields.redis_timeout.default)
      end)
      it("fields have an overwrite", function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/rate-limiting", })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_not_nil(json.fields.policy.overwrite)
        assert.is_not_nil(json.fields.redis_host.overwrite)
        assert.is_not_nil(json.fields.redis_port.overwrite)
        assert.is_not_nil(json.fields.redis_password.overwrite)
        assert.is_not_nil(json.fields.redis_database.overwrite)
        assert.is_not_nil(json.fields.redis_timeout.overwrite)
      end)
      it("policy or redis fields can not be set by user", function()
        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "rate-limiting",
            config = {
              policy = "local",
              second = 1,
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equal("policy cannot be set in your environment",
                    json["config.policy"])

        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "rate-limiting",
            config = {
              redis_host = "localhost",
              second = 1,
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equal("redis_host cannot be set in your environment",
                    json["config.redis_host"])
      end)

      it("policy and redis fields are correct overwritten", function()
        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "rate-limiting",
            config = {
              second = 1,
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal("redis", json.config.policy)
        assert.equal("a-redis-host.internal", json.config.redis_host)
        assert.equal(17812, json.config.redis_port)
        assert.equal(2000, json.config.redis_timeout)
        assert.equal(0, json.config.redis_database)
        assert.is_nil(json.config.redis_password)
      end)
    end)
  end)

  describe("[response-ratelimiting]", function()
    describe("with defaults", function()

      setup(function()
        assert(helpers.start_kong())
        client = helpers.admin_client()
        bp = helpers.get_db_utils()
      end)

      teardown(helpers.stop_kong)

      it("fields have correct defaults", function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/response-ratelimiting",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same("cluster", json.fields.policy.default)
        assert.is_nil(json.fields.redis_host.default)
        assert.same(6379, json.fields.redis_port.default)
        assert.same(0, json.fields.redis_database.default)
        assert.same(2000, json.fields.redis_timeout.default)
        assert.is_nil(json.fields.redis_password.default)
      end)
      it("fields have no overwrite", function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/response-ratelimiting",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.fields.policy.overwrite)
        assert.is_nil(json.fields.redis_host.overwrite)
        assert.is_nil(json.fields.redis_port.overwrite)
        assert.is_nil(json.fields.redis_password.overwrite)
        assert.is_nil(json.fields.redis_database.overwrite)
        assert.is_nil(json.fields.redis_timeout.overwrite)
      end)
      it("policy and redis fields can be set to a value", function()
        local route = assert(bp.routes:insert {
          hosts = { "respone-rate-limit1.test" },
        })

        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "response-ratelimiting",
            route_id = route.id,
            config = {
              policy = "local",
              redis_host = "my-redis-host.net",
              redis_port = 4242,
              redis_timeout = 120,
              redis_database = 3,
              redis_password = "password",
              limits = {
                test = {
                  second = 1,
                },
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal("local", json.config.policy)
        assert.equal("my-redis-host.net", json.config.redis_host)
        assert.equal(4242, json.config.redis_port)
        assert.equal(120, json.config.redis_timeout)
        assert.equal(3, json.config.redis_database)
        assert.equal("password", json.config.redis_password)
      end)
    end)

    describe("with feature-flag 'response_ratelimiting_restrict_redis_only=on',", function()

      setup(function()
        assert(helpers.start_kong{
          feature_conf_path = "spec-ee/fixtures/feature_rate_limit_plugins.conf",
        })
        client = helpers.admin_client()
        bp = helpers.get_db_utils()
      end)

      teardown(helpers.stop_kong)

      it("fields have no defaults", function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/response-ratelimiting",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.fields.policy.default)
        assert.is_nil(json.fields.redis_host.default)
        assert.is_nil(json.fields.redis_port.default)
        assert.is_nil(json.fields.redis_password.default)
        assert.is_nil(json.fields.redis_database.default)
        assert.is_nil(json.fields.redis_timeout.default)
      end)
      it("fields have an overwrite", function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/schema/response-ratelimiting",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_not_nil(json.fields.policy.overwrite)
        assert.is_not_nil(json.fields.redis_host.overwrite)
        assert.is_not_nil(json.fields.redis_port.overwrite)
        assert.is_not_nil(json.fields.redis_password.overwrite)
        assert.is_not_nil(json.fields.redis_database.overwrite)
        assert.is_not_nil(json.fields.redis_timeout.overwrite)
      end)
      it("policy or redis fields can not be set by user", function()
        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "response-ratelimiting",
            config = {
              policy = "local",
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equal("policy cannot be set in your environment",
                     json["config.policy"])

        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "response-ratelimiting",
            config = {
              redis_host = "localhost",
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equal("redis_host cannot be set in your environment",
                    json["config.redis_host"])
      end)

      it("policy and redis fields are correct overwritten", function()
        local res = assert(client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name = "response-ratelimiting",
            config = {
              limits = {
                test = {
                  second = 1,
                },
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal("redis", json.config.policy)
        assert.equal("a-redis-host.internal", json.config.redis_host)
        assert.equal(17812, json.config.redis_port)
        assert.equal(2000, json.config.redis_timeout)
        assert.equal(0, json.config.redis_database)
        assert.is_nil(json.config.redis_password)
      end)
    end)
  end)
end)
