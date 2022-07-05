local helpers = require "spec.helpers"

local dummy_id = "ZR02iVO6PFywzFLj6igWHd6fnK2R07C-97dkQKC7vJo"

local do_domain = "acme.noatld"
local skip_domain = "notacme.noatld"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: acme (handler.access) [#" .. strategy .. "]", function()
    local bp, db
    local proxy_client

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "certificates",
        "snis",
        "services",
        "routes",
        "plugins",
        "acme_storage",
      }, { "acme", })

      assert(bp.routes:insert {
        paths = { "/" },
      })

      assert(bp.plugins:insert {
        name = "acme",
        config = {
          account_email = "test@test.com",
          api_uri = "https://api.acme.org",
          storage = "kong",
          domains = { do_domain, "*.subdomain." .. do_domain },
        },
      })

      assert(bp.plugins:insert {
        name = "key-auth",
      })

      assert(db.acme_storage:insert {
        key = dummy_id .. "#http-01",
        value = "isme",
      })

      assert(helpers.start_kong({
        plugins = "bundled,acme",
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
        headers =  { host = do_domain }
      })

      -- key-auth should not run
      assert.response(res).has.status(404)
      body = res:read_body()
      assert.match("Not found", body)

      res = assert( proxy_client:send {
        method  = "GET",
        path    = "/.well-known/acme-challenge/" .. dummy_id,
        headers =  { host = do_domain }
      })

      -- key-auth should not run
      assert.response(res).has.status(200)
      body = res:read_body()
      assert.equal("isme\n", body)

    end)

    it("doesn't terminate validation path with host not in whitelist", function()
      local res = assert( proxy_client:send {
        method  = "GET",
        path    = "/.well-known/acme-challenge/yay",
        headers =  { host = skip_domain }
      })
      -- key-auth should take over
      assert.response(res).has.status(401)

    end)

    it("dots in wildcard in domain is escaped correctly", function()
      local res = assert( proxy_client:send {
        method  = "GET",
        path    = "/.well-known/acme-challenge/" .. dummy_id,
        headers =  { host = "a.subdomain." .. do_domain }
      })

      -- key-auth should not run
      local body = assert.response(res).has.status(200)
      assert.equal("isme", body)

      res = assert( proxy_client:send {
        method  = "GET",
        path    = "/.well-known/acme-challenge/" .. dummy_id,
        headers =  { host = "asdsubdomain." .. do_domain }
      })

      -- key-auth should take over
      assert.response(res).has.status(401)

    end)

    pending("serves default cert", function()
    end)

  end)

  describe("Plugin: acme (handler.access) allow any domain (via admin API) [#" .. strategy .. "]", function()
    local bp, db
    local proxy_client

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "certificates",
        "snis",
        "services",
        "routes",
        "plugins",
        "acme_storage",
      }, { "acme", })

      assert(bp.routes:insert {
        paths = { "/" },
      })

      assert(bp.plugins:insert {
        name = "key-auth",
      })

      assert(db.acme_storage:insert {
        key = dummy_id .. "#http-01",
        value = "isme",
      })

      assert(helpers.start_kong({
        plugins = "bundled,acme",
        database = strategy,
      }))

      local client = helpers.admin_client()
      assert(client:send({
        method = "POST",
        path = "/plugins",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          name = "acme",
          config = {
            account_email = "test@test.com",
            api_uri = "https://api.acme.org",
            storage = "kong",
            allow_any_domain = true,
          },
        },
      }))
      client:close()

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    it("allow any domain", function()
      local res
      -- wait until admin API takes effect
      helpers.wait_until(function()
        res = proxy_client:send {
          method  = "GET",
          path    = "/.well-known/acme-challenge/" .. dummy_id,
          headers =  { host = "a.subdomain." .. do_domain }
        }
        return res and res.status == 200
      end, 5)

      -- key-auth should not run
      local body = assert.response(res).has.status(200)
      assert.equal("isme", body)

      res = assert( proxy_client:send {
        method  = "GET",
        path    = "/.well-known/acme-challenge/" .. dummy_id,
        headers =  { host = "asdsubdomain." .. do_domain }
      })

      -- key-auth should not run
      local body = assert.response(res).has.status(200)
      assert.equal("isme", body)

      res = assert( proxy_client:send {
        method  = "GET",
        path    = "/.well-known/acme-challenge/" .. dummy_id,
        headers =  { skip_domain }
      })

      -- key-auth should not run
      local body = assert.response(res).has.status(200)
      assert.equal("isme", body)

    end)

  end)
end
