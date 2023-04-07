local helpers = require "spec.helpers"
local cjson = require "cjson"
local tablex = require "pl.tablex"
local stringx = require "pl.stringx"
local constants = require "kong.constants"
local utils = require "spec.helpers.perf.utils"

local NON_BUDLED_PLUGINS = {}

describe("Plugins conf property" , function()

  describe("with 'plugins=bundled'", function()
    local client
    lazy_setup(function()
      helpers.get_db_utils(nil, {}) -- runs migrations
      assert(helpers.start_kong({
        plugins = "bundled",
      }))
      client = helpers.admin_client()
    end)
    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)
    it("all bundled plugins are enabled", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
      })
      local body = assert.res_status(200 , res)
      local json = assert(cjson.decode(body))
      local bundled_plugins = constants.BUNDLED_PLUGINS
      assert.equal(tablex.size(bundled_plugins),
                   tablex.size(json.plugins.available_on_server))
    end)
    it("expect all plugins are in bundled", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
      })
      local body = assert.res_status(200 , res)
      local json = assert(cjson.decode(body))
      local bundled_plugins_list = json.plugins.available_on_server
      local rocks_installed_plugins, err = utils.execute([[luarocks show kong | grep -oP 'kong\.plugins\.\K([\w-]+)' | uniq]])
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
      assert.equal(2, tablex.size(json.plugins.available_on_server))
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

