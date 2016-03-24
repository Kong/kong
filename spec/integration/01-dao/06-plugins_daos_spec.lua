local helpers = require "spec.spec_helpers"
local Factory = require "kong.dao.factory"

helpers.for_each_dao(function(db_type, default_options, TYPES)


-- local function on_migrate(identifier)
--   print(string.format(
--     "Migrating %s (%s)",
--     identifier,
--     db_type
--   ))
-- end

-- local function on_success(identifier, migration_name)
--   print(string.format(
--     "%s migrated up to: %s",
--     identifier,
--     migration_name
--   ))
-- end

  describe("Plugins DAOs with DB: #"..db_type, function()
    it("load plugins DAOs", function()
      local factory = Factory(db_type, default_options, {"key-auth", "basic-auth", "acl", "hmac-auth", "jwt", "oauth2"})
      assert.truthy(factory.keyauth_credentials)
      assert.truthy(factory.basicauth_credentials)
      assert.truthy(factory.acls)
      assert.truthy(factory.hmacauth_credentials)
      assert.truthy(factory.jwt_secrets)
      assert.truthy(factory.oauth2_credentials)
      assert.truthy(factory.oauth2_authorization_codes)
      assert.truthy(factory.oauth2_tokens)
    end)

    describe("plugins migrations", function()
      local factory
      setup(function()
        factory = Factory(db_type, default_options, {"key-auth", "basic-auth", "acl", "hmac-auth", "jwt", "oauth2", "rate-limiting", "response-ratelimiting"})
        factory:drop_schema()
      end)
      teardown(function()
        factory:drop_schema()
      end)
      it("migrations_modules()", function()
        local migrations = factory:migrations_modules()
        assert.is_table(migrations["key-auth"])
        assert.is_table(migrations["basic-auth"])
        assert.is_table(migrations["acl"])
        assert.is_table(migrations["hmac-auth"])
        assert.is_table(migrations["jwt"])
        assert.is_table(migrations["oauth2"])
        assert.is_table(migrations["rate-limiting"])
        assert.is_table(migrations["response-ratelimiting"])
      end)

      it("run_migrations()", function()
        assert(factory:run_migrations())
      end)
    end)

    describe("custom DBs", function()
      it("loads rate-limiting custom DB", function()
        local factory = Factory(db_type, default_options, {"rate-limiting"})
        assert.truthy(factory.ratelimiting_metrics)
      end)
    end)
  end)
end)
