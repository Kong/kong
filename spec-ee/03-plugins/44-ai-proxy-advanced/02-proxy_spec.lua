-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local pl_dir = require "pl.dir"
local helpers = require "spec.helpers"

_G.lazy_setup = lazy_setup
_G.lazy_teardown = lazy_teardown
_G.before_each = before_each
_G.after_each = after_each
_G.describe = describe
_G.it = it
_G.assert = assert

local PLUGIN_NAME = "ai-proxy-advanced"


-- mangle bp.plugins to emit ai-proxy-advanced config from ai-proxy plugin config
local function patch_funcs()
  helpers._start_kong_orig = helpers.start_kong
  helpers.start_kong = function(config, ...)
    config = config or {}
    config.plugins = "bundled, ctx-checker-last, ctx-checker, " .. PLUGIN_NAME
    return helpers._start_kong_orig(config, ...)
  end
  helpers._get_db_utils_orig = helpers.get_db_utils
  helpers.get_db_utils = function(strategy, tables, _, ...)
    return helpers._get_db_utils_orig(strategy, tables, { PLUGIN_NAME, "ctx-checker-last", "ctx-checker" }, ...)
  end

  local db = require("kong.db")
  local orig_index = db.__index

  db.__index = function(t, k)
    local thing = orig_index(t, k)
    if k == "plugins" and not thing._patched then
      for _, k in ipairs({"insert", "delete", "update", "upsert"}) do
        thing["_" .. k .. "_orig"] = thing[k]
        thing[k] = function(self, payload)
          local config = payload and payload.config
          if config and payload.name == "ai-proxy" then
            config = {
              -- balancer = <default values>
              targets = { {
                auth = config.auth,
                logging = config.logging,
                model = config.model,
                route_type = config.route_type,
              } },
            }

            payload.name = PLUGIN_NAME
            payload.config = config
          end
          return thing["_" .. k .. "_orig"](self, payload)
        end
      end
      thing._patched = true
    end
    return thing
  end
end

local function restore_funcs()
  helpers.start_kong = helpers._start_kong_orig or helpers.start_kong
  helpers.get_db_utils = helpers._get_db_utils_orig or helpers.get_db_utils
  package.loaded["kong.db"] = nil
end

local ai_proxy_tests_dir = "spec/03-plugins/38-ai-proxy/"
local ai_proxy_e2e_tests = {
  openai = "02-openai_integration_spec",
  anthropic = "03-anthropic_integration_spec",
  cohere = "04-cohere_integration_spec",
  azure = "05-azure_integration_spec",
  mistral = "06-mistral_integration_spec",
  llama2 = "07-llama2_integration_spec",
  encoding = "08-encoding_integration_spec",
  streaming = "09-streaming_integration_spec",
  huggingface = "10-huggingface_integration_spec",
}


describe(PLUGIN_NAME .. " (reused tests)", function()
  setup(function()
    patch_funcs()
  end)

  teardown(function()
    restore_funcs()
  end)

  describe("sanity tests ", function()
    local admin_client

    lazy_setup(function()
      local bp = helpers.get_db_utils("postgres", nil, { "ai-proxy", PLUGIN_NAME })

      bp.plugins:insert {
        name = "ai-proxy",
        config = {
          route_type = "llm/v1/completions",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer aaaa",
          },
          model = {
            name = "gpt-3.5-turbo-instruct",
            provider = "openai",
          },
        },
      }

      assert(helpers.start_kong())

      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end
      helpers.stop_kong()
    end)

    it("creates ai-proxy-advanced plugin correctly using monkey patch", function()
      local res = admin_client:get("/plugins")
      local json = assert.response(res).has.jsonbody()
      for _, p in ipairs(json.data) do
        if p.name == PLUGIN_NAME then
          assert.same("good", "good")
          return
        end
      end

      -- fail the test
      assert.falsy("ai-proxy-advanced plugin not created")
    end)

    it("has included all ai-proxy e2e tests", function()
      local expected = {}
      for _, v in ipairs(pl_dir.getfiles(ai_proxy_tests_dir, "*.lua")) do
        -- skip 00-config and 01-unit
        if not v:match("00%-config") and not  v:match("01%-unit") then
          -- strip leading digits like "01-" and _spec.lua
          local test_name = v:match("([^/]+)%.lua$"):match("^%d+%-([^_]+)")
          expected[test_name] = v:match("([^/]+)%.lua$")
        end
      end

      assert.same(expected, ai_proxy_e2e_tests)
    end)
  end)

  for name, file in pairs(ai_proxy_e2e_tests) do
    describe("#" .. name .. ": ", function()
      require(ai_proxy_tests_dir:gsub("/", ".") .. file)
    end)
  end

end)
