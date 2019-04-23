local helpers = require "spec.helpers"
local crypto = require "kong.plugins.basic-auth.crypto"
local DB = require "kong.db"

for _, strategy in helpers.each_strategy() do

  after_each(function()
      helpers.unsetenv("KONG_PASSWORD")
      assert.equal(nil, os.getenv("KONG_PASSWORD"))
  end)

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

  describe("bootstrapping [#" .. strategy .. "]", function()
    it("creates an admin with correct basicauth ", function()
      local db = init_db()

      helpers.setenv("KONG_PASSWORD", "foo")
      assert(db:schema_reset())
      helpers.bootstrap_database(db)

      local admins = db.admins:select_all()
      assert.equal(1, #admins)

      local consumer = db.consumers:each()()
      local cred = db.basicauth_credentials:each()()
      assert.same(crypto.encrypt(consumer.id, os.getenv("KONG_PASSWORD"))  , cred.password)
    end)

  end)
end
