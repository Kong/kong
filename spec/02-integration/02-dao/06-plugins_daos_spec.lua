local helpers = require "spec.helpers"
local Factory = require "kong.dao.factory"

for conf, database in helpers.for_each_db() do
  describe("Plugins DAOs with DB: #" .. database, function()
    it("load plugins DAOs", function()
      local factory = assert(Factory.new(conf))
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
        factory = assert(Factory.new(conf))
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
    end)
  end)
end
