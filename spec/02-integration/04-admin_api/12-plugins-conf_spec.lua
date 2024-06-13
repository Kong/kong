-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local tablex = require "pl.tablex"
local stringx = require "pl.stringx"
local constants = require "kong.constants"
local utils = require "spec.helpers.perf.utils"
local ee_helpers   = require("spec-ee.helpers")
local ee_constants = require "kong.enterprise_edition.constants"
local NON_BUDLED_PLUGINS = {
  ["app-dynamics"] = true,
}

describe("Plugins conf property" , function()
  for _, portal_enabled in ipairs({ "on", "off" }) do
    describe("with 'plugins=bundled', portal enable is " .. portal_enabled .. ",", function()
      local client, reset_license_data
      lazy_setup(function()
        helpers.get_db_utils(nil, {}) -- runs migrations
        local conf = { plugins = "bundled" }
        if portal_enabled == "on" then
          reset_license_data = ee_helpers.clear_license_env()
          helpers.setenv("KONG_LICENSE_PATH", "spec-ee/fixtures/mock_license.json")
          conf = {
            plugins               = "bundled",
            portal                = true,
            portal_and_vitals_key = ee_helpers.get_portal_and_vitals_key(),
            portal_auth           = "basic-auth",
            portal_session_conf   = "{ \"secret\": \"super-secret\", \"cookie_secure\": false }",
            portal_auth_config    = "{ \"hide_credentials\": true }",
          }
        end
        assert(helpers.start_kong(conf))

        client = helpers.admin_client()
      end)
      lazy_teardown(function()
        if client then
          client:close()
        end
        helpers.stop_kong()
        if reset_license_data then
          reset_license_data()
        end
        kong.cache:invalidate(ee_constants.PORTAL_VITALS_ALLOWED_CACHE_KEY)
      end)
      it("all bundled plugins are enabled", function()
        local res = assert(client:send {
          method = "GET",
          path = "/",
        })
        local body = assert.res_status(200, res)
        local json = assert(cjson.decode(body))
        local bundled_plugins = constants.BUNDLED_PLUGINS
        local size = tablex.size(bundled_plugins)
        if portal_enabled == "off" then
          size = size - 1
        end

        assert.equal(size, tablex.size(json.plugins.available_on_server))
      end)

      it("expect all plugins are in bundled", function()
        local res = assert(client:send {
          method = "GET",
          path = "/",
        })
        local body = assert.res_status(200, res)
        local json = assert(cjson.decode(body))
        local bundled_plugins_list = json.plugins.available_on_server
        local rocks_installed_plugins, err = utils.execute(
        [[luarocks show kong | grep -o 'kong\.plugins\.\K([\w-]+)' | uniq]])
        assert.is_nil(err)
        local rocks_installed_plugins_list = stringx.split(rocks_installed_plugins, "\n")
        for _, plugin in ipairs(rocks_installed_plugins_list) do
          if not NON_BUDLED_PLUGINS[plugin] then
            assert(bundled_plugins_list[plugin] ~= nil,
              "Found installed plugin not in bundled list: " ..
              "'" .. plugin .. "'" ..
              ", please add it to the bundled list"
            )
          end
        end
      end)
    end)
  end

  describe("with 'plugins=off'", function()
    local client
    lazy_setup(function()
      assert(helpers.start_kong({
        plugins = "off",
      }))
      client = helpers.admin_client()
    end)
    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)
    it("no plugin is loaded", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
      })
      local body = assert.res_status(200 , res)
      local json = assert(cjson.decode(body))
      assert.equal(0, #json.plugins.available_on_server)
    end)
  end)

  describe("with 'plugins=off, key-auth'", function()
    local client
    lazy_setup(function()
      assert(helpers.start_kong({
        plugins = "off, key-auth",
      }))
      client = helpers.admin_client()
    end)
    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)
    it("no plugin is loaded", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
      })
      local body = assert.res_status(200 , res)
      local json = assert(cjson.decode(body))
      assert.equal(0, #json.plugins.available_on_server)
    end)
  end)

  describe("with plugins='key-auth, off, basic-auth", function()
    local client
    lazy_setup(function()
      assert(helpers.start_kong({
        plugins = "key-auth, off, basic-auth",
      }))
      client = helpers.admin_client()
    end)
    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)
    it("loads only key-auth and basic-auth plugins", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
      })
      local body = assert.res_status(200 , res)
      local json = assert(cjson.decode(body))
      -- XXX: EE, cors and session plugin are loaded by default
      assert.equal(4, tablex.size(json.plugins.available_on_server))
      assert.truthy(json.plugins.available_on_server["key-auth"])
      assert.truthy(json.plugins.available_on_server["basic-auth"])
    end)
  end)

  describe("with a plugin list in conf, admin API" , function()
    local client
    local basic_auth
    lazy_setup(function()
      assert(helpers.start_kong({
        plugins = "key-auth, basic-auth"
      }))
      client = helpers.admin_client()
    end)
    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)
    it("returns 201 for plugins included in the list" , function()
      local res = assert(client:send {
        method = "POST",
        path = "/plugins/",
        body = {
          name = "key-auth"
        },
        headers = { ["Content-Type"] = "application/json" }
      })
      assert.res_status(201 , res)

      local res = assert(client:send {
        method = "POST",
        path = "/plugins/",
        body = {
          name = "basic-auth"
        },
        headers = { ["Content-Type"] = "application/json" }
      })
      local body = assert.res_status(201 , res)
      basic_auth = assert(cjson.decode(body))
    end)
    it("returns 400 for plugins not included in the list" , function()
      local res = assert(client:send {
        method = "POST",
        path = "/plugins/",
        body = {
          name = "rate-limiting"
        },
        headers = { ["Content-Type"] = "application/json" }
      })
      assert.res_status(400 , res)
    end)

    it("update updated_at after config changed", function()
      ngx.sleep(1)
      local res = assert(client:send {
        method = "PATCH",
        path = "/plugins/" .. basic_auth.id,
        body = {
          config = {
            hide_credentials = true
          }
        },
        headers = { ["Content-Type"] = "application/json" }
      })
      local body = assert.res_status(200 , res)
      local json = assert(cjson.decode(body))
      assert.truthy(basic_auth.updated_at < json.updated_at)
    end)
  end)
end)

