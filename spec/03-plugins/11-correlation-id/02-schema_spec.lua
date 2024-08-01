local schema_def = require "kong.plugins.correlation-id.schema"
local v = require("spec.helpers").validate_plugin_config_schema
local helpers = require "spec.helpers"
local uuid = require "resty.jit-uuid"
local pgmoon_json = require("pgmoon.json")
local cjson = require "cjson"

describe("Schema: correlation-id", function ()
  it("requried field must be included", function()
    local ok, err = v({
      generator = ngx.null,
     }, schema_def)

    assert.falsy(ok)
    assert.is_not_nil(err)
    assert.equals("required field missing", err.config.generator)
  end)
end)

local strategy = "postgres"
describe("Plugin: correlation-id (schema) [#" .. strategy .."]", function()
  local admin_client, db, plugin_id
  local plugin_config = {
    generator = ngx.null,
    header_name = "Kong-Request-ID",
    echo_downstream = false,
  }

  local function render(template, keys)
    return (template:gsub("$%(([A-Z_]+)%)", keys))
  end

  setup(function()
    local plugin_name = "correlation-id"
    _, db = helpers.get_db_utils(strategy, { "plugins", "workspaces", })
    local ws = db.workspaces:select_by_name("default")
    assert.is_truthy(ws)
    plugin_id = uuid.generate_v4()
    local sql = render([[
      INSERT INTO plugins (id, name, config, enabled, ws_id) VALUES
        ('$(ID)', '$(PLUGIN_NAME)', $(CONFIG)::jsonb, TRUE, '$(WS_ID)');
      COMMIT;
    ]], {
      ID = plugin_id,
      PLUGIN_NAME = plugin_name,
      CONFIG = pgmoon_json.encode_json(plugin_config),
      WS_ID = ws.id,
    })

    local res, err = db.connector:query(sql)
    assert.is_nil(err)
    assert.is_not_nil(res)

    assert(helpers.start_kong({
      database = strategy,
      log_level = "info",
    }))
    admin_client = helpers.admin_client()
  end)

  lazy_teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  after_each(function()
    db:truncate()
  end)

  it("auto-complete generator if it is `null` in database", function()
    local sql = 'SELECT config FROM plugins WHERE id=\''.. plugin_id ..'\';'
    local res, err = db.connector:query(sql)
    assert.is_nil(err)
    assert.is_nil(res[1].generator)

    res = admin_client:get("/plugins")
    res = cjson.decode(assert.res_status(200, res))
    assert.equals(res.data[1].config.generator, "uuid#counter")
  end)
end)
