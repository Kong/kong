local cjson = require "cjson"

local uh = require "spec/upgrade_helpers"

describe("database migration", function()
    uh.old_after_up("has created the expected new columns", function()
        assert.table_has_column("targets", "cache_key", "text")
        assert.table_has_column("upstreams", "hash_on_query_arg", "text")
        assert.table_has_column("upstreams", "hash_fallback_query_arg", "text")
        assert.table_has_column("upstreams", "hash_on_uri_capture", "text")
        assert.table_has_column("upstreams", "hash_fallback_uri_capture", "text")
    end)
end)

describe("vault related data migration", function()

    local admin_client

    lazy_setup(function ()
        uh.start_kong()
        admin_client = uh.admin_client()
    end)
    lazy_teardown(function ()
        admin_client:close()
        uh.stop_kong()
    end)

    local vault = {
      name = "env",
      description = "environment vault",
      config = {prefix = "SECURE_"},
      tags = {"foo"}
    }

    local function try_put_vault(path)
      return admin_client:put(path, {
          body = vault,
          headers = {
            ["Content-Type"] = "application/json"
          }
      })
    end

    local vault_prefix = "my-vault"

    uh.setup(function ()
        local res = try_put_vault("/vaults-beta/" .. vault_prefix)
        if res.status == 404 then
          res:read_body()
          res = try_put_vault("/vaults/" .. vault_prefix)
        end
        assert.res_status(200, res)
    end)

    local function get_vault()
      local res = admin_client:get("/vaults-beta/" .. vault_prefix)
      if res.status == 404 then
        res:read_body()
        res = admin_client:get("/vaults/" .. vault_prefix)
      end
      return cjson.decode(assert.res_status(200, res))
    end

    uh.all_phases("vault exists", function ()
        local kongs_vault = get_vault()
        kongs_vault.id = nil
        kongs_vault.created_at = nil
        kongs_vault.updated_at = nil
        assert.equal(vault_prefix, kongs_vault.prefix)
        kongs_vault.prefix = nil
        assert.same(vault, kongs_vault)
    end)
end)
