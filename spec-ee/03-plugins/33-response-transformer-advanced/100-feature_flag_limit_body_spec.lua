-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local feature_flags = require "kong.enterprise_edition.feature_flags"
local VALUES = feature_flags.VALUES

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local function create_big_data(size)
  return {
    mock_json = {
      big_field = string.rep("*", size),
    },
  }
end


for _, strategy in strategies() do
  describe("Plugin: #"..strategy.." response-transformer-advanced with feature_flag response_transformation_limit_body_size on", function()
    local proxy_client
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, nil, {
        "response-transformer-advanced",
      })

      local route = bp.routes:insert({
        hosts   = { "response.test" },
        methods = { "POST" },
      })

      bp.plugins:insert {
        route    = { id = route.id },
        name     = "response-transformer-advanced",
        config   = {
          add    = {
            json = {"p1:v1"},
          }
        },
      }

      os.remove(helpers.test_conf.nginx_err_logs)

      assert(helpers.start_kong({
        database          = db_strategy,
        nginx_conf        = "spec/fixtures/custom_nginx.template",
        feature_conf_path = "spec-ee/fixtures/response_transformer/feature_response_transformer_limit_body.conf",
        plugins           = "bundled, response-transformer-advanced",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
    end)

    it("transforms body when body size doesn't exceed limit", function()
      local res = assert(proxy_client:send {
        method  = "POST",
        path    = "/post",
        body    = create_big_data(1),
        headers = {
          host             = "response.test",
          ["content-type"] = "application/json",
        }
      })
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.equal("v1", json.p1)

      -- make sure there's no error
      assert.logfile().has.no.line('is not valid number for "' .. VALUES.RESPONSE_TRANSFORMER_LIMIT_BODY_SIZE .. '"', true)
      assert.logfile().has.no.line('is turned on but "' .. VALUES.RESPONSE_TRANSFORMER_LIMIT_BODY_SIZE .. '" is not defined', true)
    end)

    it("doesn't transform body when body size exceeds limit", function()
      local body = create_big_data(1024 * 1024)
      local res = assert(proxy_client:send {
        method  = "POST",
        path    = "/post",
        body    = body,
        headers = {
          host             = "response.test",
          ["content-type"] = "application/json",
        }
      })
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.are.same(body, json.post_data.params)
      assert.is_nil(json.p1)

      -- make sure there's no error
      assert.logfile().has.no.line('is not valid number for "' .. VALUES.RESPONSE_TRANSFORMER_LIMIT_BODY_SIZE .. '"', true)
      assert.logfile().has.no.line('is turned on but "' .. VALUES.RESPONSE_TRANSFORMER_LIMIT_BODY_SIZE .. '" is not defined', true)
    end)
  end)

  describe("Plugin: #"..strategy.." response-transformer-advanced with feature_flag response_transformation_limit_body_size on, no content-length in response", function()
    local proxy_client
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, nil, {
        "response-transformer-advanced",
      })

      local route = bp.routes:insert({
        hosts   = { "response.test" },
        methods = { "GET" },
      })

      bp.plugins:insert {
        route    = { id = route.id },
        name     = "response-transformer-advanced",
        config   = {
          add    = {
            json = {"p1:v1"},
          }
        },
      }

      os.remove(helpers.test_conf.nginx_err_logs)

      assert(helpers.start_kong({
        database          = db_strategy,
        nginx_conf        = "spec/fixtures/custom_nginx.template",
        feature_conf_path = "spec-ee/fixtures/response_transformer/feature_response_transformer_limit_body_chunked.conf",
        plugins           = "bundled, response-transformer-advanced",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
    end)

    it("doesn't transform body when body size exceeds limit and content-length is not set", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/stream/1",
        headers = {
          host             = "response.test",
          ["content-type"] = "application/json",
        }
      })
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.is_nil(json.p1)
    end)
  end)

  describe("Plugin: #"..strategy.." response-transformer-advanced with feature_flag response_transformation_limit_body_size on", function()
    local proxy_client
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, nil, {
        "response-transformer-advanced",
      })

      local route = bp.routes:insert({
        hosts   = { "response.test" },
        methods = { "POST" },
      })

      bp.plugins:insert {
        route    = { id = route.id },
        name     = "response-transformer-advanced",
        config   = {
          add    = {
            json = {"p1:v1"},
          }
        },
      }

      os.remove(helpers.test_conf.nginx_err_logs)

      assert(helpers.start_kong({
        database          = db_strategy,
        nginx_conf        = "spec/fixtures/custom_nginx.template",
        feature_conf_path = "spec-ee/fixtures/response_transformer/feature_response_transformer_limit_body-body_size_not_defined.conf",
        plugins           = "bundled, response-transformer-advanced",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
    end)

    it("doesn't enable if response_transformation_limit_body_size is not defined", function()
      local res = assert(proxy_client:send {
        method  = "POST",
        path    = "/post",
        body    = create_big_data(1),
        headers = {
          host             = "response.test",
          ["content-type"] = "application/json",
        }
      })
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.equal("v1", json.p1)

      assert.logfile().has.line('is turned on but "' .. VALUES.RESPONSE_TRANSFORMER_LIMIT_BODY_SIZE .. '" is not defined', true)
    end)
  end)

  describe("Plugin: #"..strategy.." response-transformer-advanced with feature_flag response_transformation_limit_body_size on", function()
    local proxy_client
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, nil, {
        "response-transformer-advanced",
      })

      local route = bp.routes:insert({
        hosts   = { "response.test" },
        methods = { "POST" },
      })

      bp.plugins:insert {
        route    = { id = route.id },
        name     = "response-transformer-advanced",
        config   = {
          add    = {
            json = {"p1:v1"},
          }
        },
      }

      os.remove(helpers.test_conf.nginx_err_logs)

      assert(helpers.start_kong({
        database          = db_strategy,
        nginx_conf        = "spec/fixtures/custom_nginx.template",
        feature_conf_path = "spec-ee/fixtures/response_transformer/feature_response_transformer_limit_body-body_size_invalid.conf",
        plugins           = "bundled, response-transformer-advanced",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
    end)

    it("doesn't enable if response_transformation_limit_body_size is invalid", function()
      local res = assert(proxy_client:send {
        method  = "POST",
        path    = "/post",
        body    = create_big_data(1),
        headers = {
          host             = "response.test",
          ["content-type"] = "application/json",
        }
      })
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.equal("v1", json.p1)

      assert.logfile().has.line('is not valid number for "' .. VALUES.RESPONSE_TRANSFORMER_LIMIT_BODY_SIZE .. '"', true)
    end)
  end)
end
