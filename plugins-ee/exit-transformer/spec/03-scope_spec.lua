-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers    = require "spec.helpers"
local utils      = require "kong.tools.utils"
local pl_path    = require "pl.path"
local pl_file    = require "pl.file"
local pl_stringx = require "pl.stringx"
local tablex     = require "pl.tablex"
local cjson      = require "cjson"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local PLUGIN_NAME   = require("kong.plugins.exit-transformer").PLUGIN_NAME
local FILE_LOG_PATH = os.tmpname()


for _, strategy in strategies() do
  describe(PLUGIN_NAME .. ": (scope) [#" .. strategy .. "]", function()
    local client, admin_client
    local bp, gplugin
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      bp = helpers.get_db_utils(db_strategy, nil, { PLUGIN_NAME })

      local function_str_body_hello_world = [[
        return function (status, body, headers)
          body = { hello = "world" }
          return status, body, headers
        end
      ]]

      local function_str_body_another = [[
        return function (status, body, headers)
          body = { another = "transform" }
          return status, body, headers
        end
      ]]

      -- Apply plugin globally
      gplugin = bp.plugins:insert {
        name = PLUGIN_NAME,
        config = {
          functions = { function_str_body_hello_world },
        }
      }

      -- Add a plugin that generates a kong.response.exit, such as key-auth
      -- with invalid or no credentials
      bp.plugins:insert {
        name = "key-auth",
      }

      bp.routes:insert({
        hosts = { "test1.com" },
      })

      local route2 = bp.routes:insert({
        hosts = { "test2.com" },
      })

      -- Add another instance of the plugin, just to the route
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = { functions = { function_str_body_another } },
      }

      local route3 = bp.routes:insert({
        hosts = { "test3.com" },
      })

      bp.plugins:insert {
        name = "file-log",
        route = { id = route3.id },
        config = {
          path = FILE_LOG_PATH,
          reopen = true,
        },
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = db_strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- set the config item to make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,  -- since Kong CE 0.14
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
      admin_client = helpers.admin_client()
      os.remove(FILE_LOG_PATH)
    end)

    after_each(function()
      if client then client:close() end
      if admin_client then admin_client:close() end
      os.remove(FILE_LOG_PATH)
    end)

    describe("global scope", function()
      it("global plugin applies only if conf.handle_unknown", function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. gplugin.id,
          body    = {
            config = { handle_unknown = true },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)

        helpers.wait_until(function()
          -- try a request to a route that does not exist
          local res = assert(client:send {
            method = "get",
            path = "/request",  -- makes mockbin return the entire request
            headers = {
              host = "non-set-route.com"
            }
          })

          local expected_body = { hello = "world" }
          local body = res:read_body()
          local json = cjson.decode(body)
          return res.status == 404 and tablex.deepcompare(json, expected_body)
        end, 10)

        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. gplugin.id,
          body    = {
            config = { handle_unknown = false },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)

        helpers.wait_until(function()
          -- try a request to a route that does not exist
          local res = assert(client:send {
            method = "get",
            path = "/request",  -- makes mockbin return the entire request
            headers = {
              host = "non-set-route.com"
            }
          })

          local expected_message = "no Route matched with those values"
          local body = res:read_body()
          local json = cjson.decode(body)
          assert.not_nil(json)
          return res.status == 404 and json.message == expected_message
        end, 10)

      end)

      it("plugin on route applies", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test1.com"
          }
        })
        local body = res:read_body()
        assert.equal("{\"hello\":\"world\"}", body)
      end)
    end)

    describe("specific", function()
      it("plugin with another instance of the plugin also applies", function()
        local res = assert(client:send {
          method = "get",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test2.com"
          }
        })

        local body = res:read_body()
        assert.equal("{\"another\":\"transform\"}", body)
      end)
    end)

    describe("with exit-transformer + file-log configured", function()
      it("still runs the log phase plugins", function()
        local uuid = utils.random_string()
        local res = assert(client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["file-log-uuid"] = uuid,
            host = "test3.com",
          }
        })

        local body = res:read_body()
        assert.equal("{\"hello\":\"world\"}", body)

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 5)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log):match("%b{}"))
        assert.same("127.0.0.1", log_message.client_ip)
        assert.same(uuid, log_message.request.headers["file-log-uuid"])
        assert.is_number(log_message.request.size)
        assert.is_number(log_message.response.size)
      end)
    end)
  end)
end
