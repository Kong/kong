local helpers     = require "spec.helpers"
local api_helpers = require "kong.enterprise_edition.api_helpers"
local singletons  = require "kong.singletons"

for _, strategy in helpers.each_strategy() do
describe("kong.enterprise_edition.api_helpers", function()
  describe(".resolve_entity_type", function()
    local bp, new_dao, old_dao

    setup(function()
      bp, new_dao, old_dao = helpers.get_db_utils(strategy)
    end)

    it("resolves new and old daos entity types", function()
      local entities = {
        consumers = bp.consumers:insert(),
        plugins  = bp.plugins:insert({name = "dummy"}),
        services = bp.services:insert(),
        routes = bp.routes:insert({methods = {"GET"}, hosts = {"example.com"}}),
      }
      for entity_type, entity in pairs(entities) do
        local typ, _, err = api_helpers.resolve_entity_type(new_dao, old_dao,
          entity.id)
        assert.equal(typ, entity_type)
        assert.is_nil(err)
      end
    end)
  end)

  describe(".prepare_plugin", function()
    local old_dao, conf

    singletons.loaded_plugins = {
      { name = "session" }
    }

    setup(function()
      _, _, old_dao = helpers.get_db_utils(strategy)
    end)

    before_each(function()
      conf = {
        cookie_name =  "yeee boi. Im a cookie!",
        secret = "secret squirrel"
      }
    end)

    it("#flaky returns config with defaults applied", function()
      local prepared_plugin = api_helpers.prepare_plugin(api_helpers.apis.PORTAL,
      old_dao, "session", conf)

      assert.same({
        config = {
          cookie_discard = 10,
          cookie_httponly = true,
          cookie_lifetime = 3600,
          cookie_name = "yeee boi. Im a cookie!",
          cookie_path = "/",
          cookie_renew = 600,
          cookie_samesite = "Strict",
          cookie_secure = true,
          logout_methods = { "POST", "DELETE" },
          logout_post_arg = "session_logout",
          logout_query_arg = "session_logout",
          secret = "secret squirrel",
          storage = "cookie"
        }
      }, prepared_plugin)

    end)

    it("does not mutate the passed conf table", function()
      api_helpers.prepare_plugin(api_helpers.apis.PORTAL, old_dao, "session",
                                                                          conf)

        assert.same({
          cookie_name =  "yeee boi. Im a cookie!",
          secret = "secret squirrel",
        }, conf)
    end)
  end)
end)
end
