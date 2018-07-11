local helpers = require "spec.helpers"
local feature_flags = require "kong.enterprise_edition.feature_flags"
local VALUES = feature_flags.VALUES

local pl_file = require "pl.file"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: request-transformer [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)
      local route1 = bp.routes:insert({
        hosts = { "test1.com" },
      })

      bp.plugins:insert {
        route_id = route1.id,
        name     = "request-transformer",
        config   = {
          add = {
            body        = {"p1:v1"}
          }
        }
      }

      assert(helpers.start_kong({
        database          = strategy,
        nginx_conf        = "spec/fixtures/custom_nginx.template",
        feature_conf_path = "spec/fixtures/ee/request_transformer/feature_request_transformer_limit_body.conf",
      }))
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)


    describe("with feature_flag request_transformation_limit_body on", function()
      it("changes body if request body size is less than limit", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            hello = "world",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test1.com"
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.formparam("hello")
        assert.equals("world", value)
        local value = assert.request(res).has.formparam("p1")
        assert.equals("v1", value)

        -- make sure there's no error
        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.not_matches(string.format(
                           "is turned on but \"%s\" is not defined", VALUES.REQUEST_TRANSFORMER_LIMIT_BODY_SIZE),
                           err_log, nil, true)
        assert.not_matches(string.format(
                           "is not valid number for \"%s\"", VALUES.REQUEST_TRANSFORMER_LIMIT_BODY_SIZE),
                           err_log, nil, true)

      end)
    end)
    it("doesn't change body if request body size is bigger than limit", function()
      local payload = string.rep("*", 128)
      local res = assert(proxy_client:send {
        method  = "POST",
        path    = "/request",
        body    = {
          hello = payload
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host             = "test1.com"
        }
      })
      assert.response(res).has.status(200)
      local value = assert.request(res).has.formparam("hello")
      assert.equals(payload, value)
      assert.request(res).has.no.formparam("p1")

      -- make sure there's no error
      local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
      assert.not_matches(string.format(
                         "is turned on but \"%s\" is not defined", VALUES.REQUEST_TRANSFORMER_LIMIT_BODY_SIZE),
                         err_log, nil, true)
      assert.not_matches(string.format(
                         "is not valid number for \"%s\"", VALUES.REQUEST_TRANSFORMER_LIMIT_BODY_SIZE),
                         err_log, nil, true)
    end)
  end)

  describe("Plugin: request-transformer [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local route1 = bp.routes:insert({
        hosts = { "test1.com" },
      })

      bp.plugins:insert {
        route_id = route1.id,
        name     = "request-transformer",
        config   = {
          add = {
            body        = {"p1:v1"}
          }
        }
      }

      assert(helpers.start_kong({
        database          = strategy,
        nginx_conf        = "spec/fixtures/custom_nginx.template",
        feature_conf_path = "spec/fixtures/ee/request_transformer/feature_request_transformer_limit_body-body_size_not_defined.conf",
      }))
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)


    describe("with feature_flag request_transformation_limit_body on", function()
      it("doesn't enable if request_transformation_limit_body_size is not defined", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            hello = "world",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test1.com"
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.formparam("hello")
        assert.equals("world", value)
        local value = assert.request(res).has.formparam("p1")
        assert.equals("v1", value)

        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.matches(string.format(
                       "is turned on but \"%s\" is not defined", VALUES.REQUEST_TRANSFORMER_LIMIT_BODY_SIZE),
                       err_log, nil, true)
      end)
    end)
  end)

  describe("Plugin: request-transformer [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local route1 = bp.routes:insert({
        hosts = { "test1.com" },
      })

      bp.plugins:insert {
        route_id = route1.id,
        name     = "request-transformer",
        config   = {
          add = {
            body        = {"p1:v1"}
          }
        }
      }

      assert(helpers.start_kong({
        database          = strategy,
        nginx_conf        = "spec/fixtures/custom_nginx.template",
        feature_conf_path = "spec/fixtures/ee/request_transformer/feature_request_transformer_limit_body-body_size_invalid.conf",
      }))
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)


    describe("with feature_flag request_transformation_limit_body on", function()
      it("doesn't enable if request_transformation_limit_body_size is invalid", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            hello = "world",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test1.com"
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.formparam("hello")
        assert.equals("world", value)
        local value = assert.request(res).has.formparam("p1")
        assert.equals("v1", value)

        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.matches(string.format(
                       "is not valid number for \"%s\"", VALUES.REQUEST_TRANSFORMER_LIMIT_BODY_SIZE),
                       err_log, nil, true)
      end)
    end)
  end)
end
