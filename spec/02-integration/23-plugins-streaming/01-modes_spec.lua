-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local cjson = require "cjson"
local helpers = require "spec.helpers"


local it = it
local pcall = pcall
local ipairs = ipairs
local assert = assert
local describe = describe
local lazy_setup = lazy_setup
local after_each = after_each
local before_each = before_each
local lazy_teardown = lazy_teardown


local CUSTOM_PLUGIN_NAME = "set-header"
local CUSTOM_PLUGIN_SCHEMA = [[
return {
  name = "set-header",
  fields = {
    { protocols = require("kong.db.schema.typedefs").protocols_http },
    { config = {
      type = "record",
      fields = {
        { name = { description = "The name of the header to set.", type = "string", required = true } },
        { value = { description = "The value for the header.", type = "string", required = true } },
      } },
    },
  },
}
]]
local CUSTOM_PLUGIN_HANDLER = [[
return {
  VERSION = "1.0,0",
  PRIORITY = 500,
  access = function(_, config)
    kong.service.request.set_header(config.name, config.value)
  end
}
]]


local HEADER_NAME = "set-header-name"
local HEADER_VALUE = "set-header-value"


local function initialize_db(strategy)
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
    config = {
      name = HEADER_NAME,
      value = HEADER_VALUE,
    },
  })
end


for _, strategy in helpers.each_strategy() do
  describe("Plugins Streaming", function()
    local proxy_client
    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    local function works()
      local res, err = proxy_client:get("/")
      assert.is_nil(err)
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json)
      assert.is_equal(HEADER_VALUE, json.headers[HEADER_NAME])
      return true
    end

    describe("Non-Hybrid #" .. strategy, function()
      lazy_setup(function()
        initialize_db(strategy)
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

      it("works", works)
    end)

    for _, toggle in ipairs(strategy ~= "off" and { "on", "off" } or {}) do
      describe("Hybrid #" .. strategy .. " incremental=" .. toggle, function()
        lazy_setup(function()
          initialize_db(strategy)
          helpers.start_kong({
            role = "control_plane",
            plugins = "",
            database = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            custom_plugins_enabled = "on",
            cluster_listen = "127.0.0.1:9005",
            cluster_cert = "spec/fixtures/kong_clustering.crt",
            cluster_cert_key = "spec/fixtures/kong_clustering.key",
          })
          helpers.start_kong({
            role = "data_plane",
            prefix = "servroot2",
            plugins = "",
            database = "off",
            nginx_conf = "spec/fixtures/custom_nginx.template",
            custom_plugins_enabled = "on",
            cluster_control_plane = "127.0.0.1:9005",
            cluster_cert = "spec/fixtures/kong_clustering.crt",
            cluster_cert_key = "spec/fixtures/kong_clustering.key",
            cluster_incremental_sync = toggle,
            worker_state_update_frequency = 1,
          })
        end)

        lazy_teardown(function()
          helpers.stop_kong("servroot2")
          helpers.stop_kong()
        end)

        it("works", function()
          helpers.wait_until(function()
            local pok, ok = pcall(works)
            if pok and ok then
              return true
            end
          end, 10)
        end)
      end)
    end
  end)
end
