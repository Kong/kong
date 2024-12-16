-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local cjson = require "cjson"
local helpers = require "spec.helpers"
local random_string = require("kong.tools.rand").random_string


local it = it
local assert = assert
local describe = describe
local lazy_setup = lazy_setup
local after_each = after_each
local before_each = before_each
local lazy_teardown = lazy_teardown


local CUSTOM_PLUGIN_NAME = "sandbox-tester"
local CUSTOM_PLUGIN_SCHEMA = [[
return {
  name = "sandbox-tester",
  fields = {
    { protocols = require("kong.db.schema.typedefs").protocols_http },
    { config = { type = "record", fields = {} } },
  },
}
]]
local CUSTOM_PLUGIN_HANDLER = [[
local random_string = require("kong.tools.rand").random_string
return {
  VERSION = "1.0,0",
  PRIORITY = 500,
  certificate = function()
    ngx.ctx.con = random_string()
  end,
  rewrite = function()
    ngx.ctx.req_header = kong.request.get_header("Request-Header")
  end,
  access = function()
    kong.response.exit(200, {
      connection = {
        con = ngx.ctx.connection.con,
      },
      req_header = ngx.ctx.req_header,
    })
  end
}
]]


for _, strategy in helpers.each_strategy() do
  describe("Plugins Streaming Sandbox #" .. strategy, function()
    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "custom_plugins",
      })

      bp.routes:insert({
        paths = { "/" },
        service = bp.services:insert(),
      })

      bp.custom_plugins:insert({
        name = CUSTOM_PLUGIN_NAME,
        schema = CUSTOM_PLUGIN_SCHEMA,
        handler = CUSTOM_PLUGIN_HANDLER,
      })

      bp.plugins:insert({
        name = CUSTOM_PLUGIN_NAME,
      })

      helpers.start_kong({
        plugins = "",
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        custom_plugins_enabled = "on",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    local proxy_ssl_client
    before_each(function()
      proxy_ssl_client = helpers.proxy_ssl_client()
    end)

    after_each(function()
      if proxy_ssl_client then
        proxy_ssl_client:close()
      end
    end)

    it("handles context correctly", function()
      local req_header = random_string()
      local res, err
      res, err = proxy_ssl_client:get("/", {
        headers = {
          ["Request-Header"] = req_header,
        },
      })
      assert.is_nil(err)
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local con_value = json.connection.con
      assert.same({
        connection = {
          con = con_value,
        },
        req_header = req_header,
      }, json)

      -- now let's fire a second request and see that connection
      -- ctx is properly kept from the previous request

      req_header = random_string()
      res, err = proxy_ssl_client:get("/", {
        headers = {
          ["Request-Header"] = req_header,
        },
      })
      assert.is_nil(err)
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.same({
        connection = {
          con = con_value,
        },
        req_header = req_header,
      }, json)
    end)
  end)
end
