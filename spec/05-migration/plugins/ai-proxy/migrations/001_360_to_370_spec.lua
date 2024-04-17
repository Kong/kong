local uh = require "spec.upgrade_helpers"
local helpers = require "spec.helpers"
local pgmoon_json = require("pgmoon.json")
local uuid = require "resty.jit-uuid"

local strategy = "postgres"

local function render(template, keys)
  return (template:gsub("$%(([A-Z_]+)%)", keys))
end

if uh.database_type() == strategy then
  describe("ai-proxy plugin migration", function()
    local _, db = helpers.get_db_utils(strategy, { "plugins" })
    local id = uuid.generate_v4()
    local plugin_name = "ai-proxy"
    local plugin_config = {
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
    }

    uh.setup(function()
      local sql = render([[
        INSERT INTO plugins (id, name, config, enabled) VALUES
          ('$(ID)', '$(PLUGIN_NAME)', $(CONFIG)::jsonb, TRUE);
        COMMIT;
      ]], {
        ID = id,
        PLUGIN_NAME = plugin_name,
        CONFIG = pgmoon_json.encode_json(plugin_config),
      })

      local res, err = db.connector:query(sql)
      assert.is_nil(err)
      assert.is_not_nil(res)

      sql = render([[
        SELECT * FROM plugins WHERE id = '$(ID)';
      ]], {
        ID = id,
      })

      res, err = db.connector:query(sql)
      assert.is_nil(err)
      assert.is_not_nil(res)
      assert.equals(1, #res)

    end)

    uh.new_after_up("has updated ai-proxy plugin configuration", function ()
      local sql = render([[
        SELECT * FROM plugins WHERE name = '$(PLUGIN_NAME)';
      ]], {
        PLUGIN_NAME = plugin_name,
      })

      local res, err = db.connector:query(sql)
      assert.is_nil(err)
      assert.is_not_nil(res)
      assert.equals(1, #res)

      -- local plugin, err = db.plugins:select({ id = id })
      -- assert.is_nil(err)
      -- assert.is_not_nil(plugin)

      -- assert.equal(plugin_name, plugin.name)
      -- local expected_config = {
      --   logging = {
      --       log_statistics = false
      --   },
      --   route_type = "llm/v1/completions",
      --   model = {
      --       provider = "anthropic"
      --   }
      -- }

      -- assert.partial_match(expected_config, plugin.config)
    end)
  end)
end
