local uh = require "spec.upgrade_helpers"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("ai-proxy plugin migration", function()
    local db, ai_proxy_plugin
    uh.setup(function()
      _, db = helpers.get_db_utils(strategy, {"plugins"}, { "ai-proxy" })
      local plugin, err, err_t = db.plugins:insert {
        name = "ai-proxy",
        config = {
          route_type = "llm/v1/completions",
          auth = {
            header_name = "x-api-key",
            header_value = "anthropic-key",
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://example.com/llm/v1/completions/good",
              anthropic_version = "2023-06-01",
            },
          },
          logging = {
            log_statistics = true,  -- anthropic does not support statistics
          },
        },
      }
      assert.is_nil(err)
      assert.is_nil(err_t)
      assert.is_not_nil(plugin)
      ai_proxy_plugin = plugin
    end)

    uh.new_after_up("has updated ai-proxy plugin configuration", function ()
      -- local cache_key = db.plugins:cache_key("ai-proxy")
      local plugin, err = db.plugins:select({ id = ai_proxy_plugin.id })
      assert.is_nil(err)
      assert.is_not_nil(plugin)
      -- assert.equal(1, #rows)

      assert.equal("ai-proxy", plugin.name)
      local expected_config = {
        logging = {
            log_statistics = false
        },
        route_type = "llm/v1/completions",
        model = {
            provider = "anthropic"
        }
      }

      assert.partial_match(expected_config, plugin.config)
    end)
  end)
end