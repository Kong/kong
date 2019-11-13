local helpers = require "spec.helpers"

local dummy_id = "ZR02iVO6PFywzFLj6igWHd6fnK2R07C-97dkQKC7vJo"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: letsencrypt (client.save) [#" .. strategy .. "]", function()
    local bp, db
    local proxy_client

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "certificates",
        "snis",
        "services",
        "routes",
        "plugins",
        "letsencrypt_storage",
      }, { "letsencrypt", })

      local route = bp.routes:insert {
        hosts = { "letsencrypt.test" },
      }

      bp.plugins:insert {
        route = route,
        name = "letsencrypt",
        config = {
          account_email = "test@test.com",
          staging = true,
        }
      }

      db.letsencrypt_storage:insert {
        key = dummy_id,
        value = "isme",
      }

      assert(helpers.start_kong({
        plugins = "bundled,letsencrypt",
        database = strategy,
      }))

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    it("terminates validation path", function()
      local body
      local res = assert( proxy_client:send {
        method  = "GET",
        path    = "/.well-known/acme-challenge/yay",
        headers =  { host = "letsencrypt.test" }
      })
      assert.response(res).has.status(404)
      body = res:read_body()
      assert.equal("Not found\n", body)

      res = assert( proxy_client:send {
        method  = "GET",
        path    = "/.well-known/acme-challenge/" .. dummy_id,
        headers =  { host = "letsencrypt.test" }
      })
      assert.response(res).has.status(200)
      body = res:read_body()
      assert.equal("isme\n", body)

    end)

    pending("serves default cert", function()
    end)

  end)
end
