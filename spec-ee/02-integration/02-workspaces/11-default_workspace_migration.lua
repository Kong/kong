local helpers = require "spec.helpers"
local DB = require "kong.db"


for _, strategy in helpers.each_strategy() do

  local function init_db()
    local db = assert(DB.new(helpers.test_conf, strategy))
    assert(db:init_connector())
    assert(db:connect())
    finally(function()
      db.connector:close()
    end)
    assert(db.plugins:load_plugin_schemas(helpers.test_conf.loaded_plugins))
    return db
  end

  describe("default workspace after migrations [#" .. strategy .. "]", function()
    it("is contains the correct defaults", function()
      local db = init_db()

      assert(db:schema_reset())
      helpers.bootstrap_database(db)

      local workspaces = db.workspaces:select_all()
      local default_ws = workspaces[1]

      assert.equal(1, #workspaces)
      assert.equal("default", default_ws.name)
      assert.equal("00000000-0000-0000-0000-000000000000", default_ws.id)
      assert.same({}, default_ws.meta)
      assert.same({ portal = false }, default_ws.config)
    end)
  end)
end
