local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local DB = require "kong.db"


for _, strategy in helpers.each_strategy() do

  local function init_db()
    local conf = utils.deep_copy(helpers.test_conf)
    conf.cassandra_timeout = 60000 -- default used in the `migrations` cmd as well
    local db = assert(DB.new(conf, strategy))
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
      assert.same({}, default_ws.meta)
      assert.equal(false , default_ws.config.portal)
    end)
  end)
end
