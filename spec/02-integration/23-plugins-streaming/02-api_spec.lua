-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local cjson = require "cjson"
local helpers = require "spec.helpers"


local it = it
local null = ngx.null
local pcall = pcall
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
        { name = { description = "The name of the header to set.", type = "string", required = true, } },
        { value = { description = "The value for the header.", type = "string", required = true, } },
      },
    } },
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


local DBLESS_CONFIG = [[
_format_version: "3.0"
custom_plugins:
- name: set-header
  schema: |
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
  handler: |
    return {
      VERSION = "1.0,0",
      PRIORITY = 500,
      access = function(_, config)
        kong.service.request.set_header(config.name, config.value)
      end
    }
plugins:
- name: set-header
  instance_name: set-header
  config:
    name: set-header-name
    value: set-header-value
]]
local DBLESS_EMPTY_CONFIG = [[
_format_version: "3.0"
]]


local ADMIN_CLIENT_JSON_HEADERS = {
  ["Content-Type"] = "application/json; charset=utf-8",
}
local ADMIN_CLIENT_YAML_HEADERS = {
  ["Content-Type"] = "application/yaml; charset=utf-8",
}


for _, strategy in helpers.each_strategy() do
  describe("Plugins Streaming API #" .. strategy, function()
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

    local admin_client, proxy_client
    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
    end)

    local function get_plugin(expected_status)
      local res, err = admin_client:get("/plugins/" .. CUSTOM_PLUGIN_NAME)
      assert.is_nil(err)
      local body = assert.res_status(expected_status or 200, res)
      local json = cjson.decode(body)
      assert.is_table(json)
      return json
    end

    local function put_plugin()
      local res, err = admin_client:put("/plugins/" .. CUSTOM_PLUGIN_NAME, {
        headers = ADMIN_CLIENT_JSON_HEADERS,
        body = {
          name = CUSTOM_PLUGIN_NAME,
          config = {
            name = HEADER_NAME,
            value = HEADER_VALUE,
          },
        },
      })
      assert.is_nil(err)
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json)
      assert.is_equal(CUSTOM_PLUGIN_NAME, json.name)
      return json
    end

    local function delete_plugin(plugin)
      local res, err = admin_client:delete("/plugins/" .. plugin.id)
      assert.is_nil(err)
      local body = assert.res_status(204, res)
      assert.is_equal("", body)
    end

    local function get_custom_plugins()
      local res, err = admin_client:get("/custom-plugins")
      assert.is_nil(err)
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json)
      assert.is_table(json.data)
      return json
    end

    local function get_custom_plugin(expected_status)
      local res, err = admin_client:get("/custom-plugins/" .. CUSTOM_PLUGIN_NAME)
      assert.is_nil(err)
      local body = assert.res_status(expected_status or 200, res)
      local json = cjson.decode(body)
      assert.is_table(json)
      return json
    end

    local function delete_custom_plugin(custom_plugin, expected_status, expected_message)
      local res, err = admin_client:delete("/custom-plugins/" .. custom_plugin.id)
      assert.is_nil(err)
      local body = assert.res_status(expected_status or 204, res)
      if expected_status then
        local json = cjson.decode(body)
        assert.is_equal(expected_message, json.name)
      else
        assert.is_equal("", body)
      end
    end

    local function post_custom_plugin(expected_status, expected_message, name, schema, handler)
      local res, err = admin_client:post("/custom-plugins", {
        headers = ADMIN_CLIENT_JSON_HEADERS,
        body = {
          name = name or CUSTOM_PLUGIN_NAME,
          schema = schema or CUSTOM_PLUGIN_SCHEMA,
          handler = handler or CUSTOM_PLUGIN_HANDLER,
        },
      })
      assert.is_nil(err)
      local body = assert.res_status(expected_status or 201, res)
      local json = cjson.decode(body)
      assert.is_table(json)
      assert.is_equal(expected_message or CUSTOM_PLUGIN_NAME, json.name)
      return json
    end

    local function put_custom_plugin(expected_status, expected_message)
      local res, err = admin_client:put("/custom-plugins/" .. CUSTOM_PLUGIN_NAME, {
        headers = ADMIN_CLIENT_JSON_HEADERS,
        body = {
          schema = CUSTOM_PLUGIN_SCHEMA,
          handler = CUSTOM_PLUGIN_HANDLER,
        },
      })
      assert.is_nil(err)
      local body = assert.res_status(expected_status or 200, res)
      local json = cjson.decode(body)
      assert.is_table(json)
      assert.is_equal(expected_message or CUSTOM_PLUGIN_NAME, json.name)
      return json
    end

    local function patch_custom_plugin(expected_status, expected_message)
      local res, err = admin_client:patch("/custom-plugins/" .. CUSTOM_PLUGIN_NAME, {
        headers = ADMIN_CLIENT_JSON_HEADERS,
        body = {
          schema = CUSTOM_PLUGIN_SCHEMA,
          handler = CUSTOM_PLUGIN_HANDLER,
        },
      })
      assert.is_nil(err)
      local body = assert.res_status(expected_status or 200, res)
      local json = cjson.decode(body)
      assert.is_table(json)
      assert.is_equal(expected_message or CUSTOM_PLUGIN_NAME, json.name)
      return json
    end

    local function get_custom_plugin_schema(expected_status)
      local res, err = admin_client:get("/schemas/plugins/" .. CUSTOM_PLUGIN_NAME)
      assert.is_nil(err)
      local body = assert.res_status(expected_status or 200, res)
      local json = cjson.decode(body)
      assert.is_table(json)
      return json
    end

    local function wait_custom_plugin_schema(expected_status)
      helpers.wait_until(function()
        local pok, ok = pcall(get_custom_plugin_schema, expected_status)
        if pok and ok then
          return true
        end
      end, 10)
    end

    local function post_config(config)
      local res, err = admin_client:post("/config", {
        headers = ADMIN_CLIENT_YAML_HEADERS,
        body = config or DBLESS_CONFIG,
      })
      assert.is_nil(err)
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      assert.is_table(json)
      return json
    end

    if strategy ~= "off" then
      describe("/custom-plugins", function()
        describe("GET", function()
          it("lists custom plugins", function()
            local custom_plugins = get_custom_plugins()
            assert.is_equal(null, custom_plugins.next)
            local custom_plugin = put_custom_plugin()
            custom_plugins = get_custom_plugins()
            assert.is_equal(1, #custom_plugins.data)
            assert.same(custom_plugin, custom_plugins.data[1])
            delete_custom_plugin(custom_plugin)
          end)
        end)
        describe("POST", function()
          it("creates a custom plugin", function()
            delete_custom_plugin(post_custom_plugin())
            local custom_plugin = post_custom_plugin()
            post_custom_plugin(409, "unique constraint violation")
            delete_custom_plugin(custom_plugin)
          end)
          it("errors on invalid input", function()
            post_custom_plugin(400, "schema violation", nil, "does-not-match-schema-name")
            post_custom_plugin(400, "schema violation", nil, 'for each item in items do\nprint(item)\nend')
            post_custom_plugin(400, "schema violation", nil, 'error("should not work")')
            post_custom_plugin(400, "schema violation", nil, nil, 'ngx.timer.at(0, function() end)\n' .. CUSTOM_PLUGIN_SCHEMA)
            post_custom_plugin(400, "schema violation", nil, 'require("inspect")\n' .. CUSTOM_PLUGIN_SCHEMA)

            post_custom_plugin(400, "schema violation", nil, nil, 'for each item in items do\nprint(item)\nend')
            post_custom_plugin(400, "schema violation", nil, nil, 'error("should not work")')
            post_custom_plugin(400, "schema violation", nil, nil, 'ngx.timer.at(0, function() end)\n' .. CUSTOM_PLUGIN_HANDLER)
            post_custom_plugin(400, "schema violation", nil, nil, 'require("inspect")\n' .. CUSTOM_PLUGIN_HANDLER)
            post_custom_plugin(400, "schema violation", nil, nil, [[
            return {
              VERSION = "1.0,0",
              PRIORITY = "test",
              access = function(_, config)
                kong.service.request.set_header(config.name, config.value)
              end
            }]])
            post_custom_plugin(400, "schema violation", nil, nil, [[
            return {
              VERSION = "latest",
              PRIORITY = 500,
              access = function(_, config)
                kong.service.request.set_header(config.name, config.value)
              end
            }]])
            post_custom_plugin(400, "schema violation", nil, nil, [[
            return {
              VERSION = "1.0.0",
              PRIORITY = 500,
              init_worker = function()
                kong.log.err("init worker is not allowed")
              end
            }]])
          end)
        end)
      end)

      describe("/custom-plugins/<name>", function()
        describe("GET", function()
          it("returns a custom plugin", function()
            get_custom_plugin(404)
            local custom_plugin = put_custom_plugin()
            local read_custom_plugin = get_custom_plugin()
            assert.same(custom_plugin, read_custom_plugin)
            delete_custom_plugin(custom_plugin)
          end)
        end)
        describe("PUT", function()
          it("replaces a custom plugin", function()
            delete_custom_plugin(put_custom_plugin())
            put_custom_plugin()
            delete_custom_plugin(put_custom_plugin())
          end)
          it("doesn't allow replacing a configured custom plugin", function()
            put_custom_plugin()
            local plugin = put_plugin()
            put_custom_plugin(400, "referenced by others")
            delete_plugin(plugin)
            delete_custom_plugin(patch_custom_plugin())
          end)
        end)
        describe("PATCH", function()
          it("updates a custom plugin", function()
            put_custom_plugin()
            patch_custom_plugin()
            delete_custom_plugin(patch_custom_plugin())
          end)
          it("doesn't allow updating a configured custom plugin", function()
            put_custom_plugin()
            local plugin = put_plugin()
            patch_custom_plugin(400, "referenced by others")
            delete_plugin(plugin)
            delete_custom_plugin(patch_custom_plugin())
          end)
        end)
        describe("DELETE", function()
          it("deletes a custom plugin", function()
            put_custom_plugin()
            delete_custom_plugin(get_custom_plugin())
            get_custom_plugin(404)
          end)
          it("doesn't allow deleting a configured custom plugin", function()
            local custom_plugin = put_custom_plugin()
            local plugin = put_plugin()
            delete_custom_plugin(custom_plugin, 400, "referenced by others")
            delete_plugin(plugin)
            delete_custom_plugin(custom_plugin)
          end)
        end)
      end)
      describe("/schemas/plugins/<name>", function()
        describe("GET", function()
          wait_custom_plugin_schema(404)
          local custom_plugin = put_custom_plugin()
          wait_custom_plugin_schema()
          delete_custom_plugin(custom_plugin)
          wait_custom_plugin_schema(404)
        end)
      end)

    else -- "off" strategy
      describe("/config", function()
        describe("POST", function()
          it("applies configuration with custom plugins", function()
            post_config()
            get_custom_plugin()
            get_plugin()
            wait_custom_plugin_schema()
            post_config(DBLESS_EMPTY_CONFIG)
            get_custom_plugin(404)
            get_plugin(404)
            wait_custom_plugin_schema(404)
          end)
        end)
      end)
    end
  end)
end
