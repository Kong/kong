local helpers = require "spec.helpers"

describe("OpenResty phases", function()
  describe("rewrite_by_lua", function()
    describe("enabled on all APIs", function()
      local api_client, proxy_client

      lazy_setup(function()
        local dao = select(3, helpers.get_db_utils())

        -- insert plugin-less api and a global plugin
        assert(dao.apis:insert {
          name         = "mock_upstream",
          hosts        = { "mock_upstream" },
          upstream_url = helpers.mock_upstream_url,
        })
        assert(dao.plugins:insert {
          name   = "rewriter",
          config = {
            value = "global plugin",
          },
        })

        assert(helpers.start_kong({
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        api_client   = helpers.admin_client()
        proxy_client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if api_client then api_client:close() end
        helpers.stop_kong()
      end)

      it("runs", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.header("rewriter")
        assert.equal("global plugin", value)
      end)
    end)

    describe("enabled on a specific APIs", function()
      local api_client, proxy_client

      lazy_setup(function()
        local dao = select(3, helpers.get_db_utils())

        -- api specific plugin
        local api2 = assert(dao.apis:insert {
          name         = "mock_upstream",
          hosts        = { "mock_upstream" },
          upstream_url = helpers.mock_upstream_url,
        })
        assert(dao.plugins:insert {
          api = { id = api2.id },
          name   = "rewriter",
          config = {
            value = "api-specific plugin",
          },
        })

        assert(helpers.start_kong({
          nginx_conf = "spec/fixtures/custom_nginx.template"
        }))

        api_client = helpers.admin_client()
        proxy_client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if api_client then api_client:close() end
        helpers.stop_kong()
      end)

      it("doesn't run", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("rewriter")
      end)
    end)

    describe("enabled on a specific Consumers", function()
      local api_client, proxy_client

      lazy_setup(function()
        local bp, _, dao = helpers.get_db_utils()

        -- consumer specific plugin
        local api3 = assert(dao.apis:insert {
          name         = "mock_upstream",
          hosts        = { "mock_upstream" },
          upstream_url = helpers.mock_upstream_url,
        })
        assert(dao.plugins:insert {
          api = { id = api3.id },
          name   = "key-auth",
        })
        local consumer3 = bp.consumers:insert {
          username = "test-consumer",
        }
        bp.keyauth_credentials:insert {
          key      = "kong",
          consumer = { id = consumer3.id },
        }
        assert(dao.plugins:insert {
          consumer = { id = consumer3.id },
          name        = "rewriter",
          config      = {
            value = "consumer-specific plugin",
          },
        })

        assert(helpers.start_kong({
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        api_client = helpers.admin_client()
        proxy_client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if api_client then api_client:close() end
        helpers.stop_kong()
      end)

      it("doesn't run", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host   = "mock_upstream",
            apikey = "kong",
          },
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.header("x-consumer-username")
        assert.equal("test-consumer", value)
        assert.request(res).has.no.header("rewriter")
      end)
    end)
  end)
end)
