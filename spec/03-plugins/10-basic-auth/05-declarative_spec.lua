local declarative = require "kong.db.declarative"
local helpers = require "spec.helpers"
local crypto = require "kong.plugins.basic-auth.crypto"
local cjson   = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("basic-auth declarative config #" .. strategy, function()
    local db
    lazy_setup(function()
      local _
      _, db = helpers.get_db_utils(strategy)
--      _G.kong.db = db
    end)

    lazy_teardown(function()
--      assert(helpers.stop_kong())
    end)

    local service_def = {
      _tags = ngx.null,
      connect_timeout = 60000,
      created_at = 1549025889,
      host = helpers.mock_upstream_hostname,
      id = "3b9c2302-a610-4925-a7b9-25942309335d",
      name = "foo",
      path = ngx.null,
      port = helpers.mock_upstream_port,
      protocol = helpers.mock_upstream_protocol,
      read_timeout = 60000,
      retries = 5,
      updated_at = 1549025889,
      write_timeout = 60000,
    }

    local route_def = {
      _tags = ngx.null,
      created_at = 1549025889,
      id = "eb88ccb8-274d-4e7e-b4cb-0d673a4fa93b",
      name = "bar",
      protocols = { "http" },
      methods = ngx.null,
      hosts = ngx.null,
      paths = { "/" },
      regex_priority = 0,
      strip_path = true,
      preserve_host = false,
      snis = ngx.null,
      sources = ngx.null,
      destinations = ngx.null,
      service = { id = service_def.id },
    }

    local consumer_def = {
      _tags = ngx.null,
      created_at = 1549476023,
      id = "ad06b77c-0d2f-407a-8d6d-07f272a92d6a",
      username = "andru",
      custom_id = "donalds",
    }

    local basicauth_credential_def = {
      id = "ad06b77c-0d2f-407a-8d6d-07f272a92d9a",
      consumer = {
        id = consumer_def.id,
      },
      username = "james",
      password = "secret",
    }

    local plugin_def = {
      _tags = ngx.null,
      created_at = 1547047308,
      id = "389ad9bd-b158-4e19-aed7-c9b040f7f312",
      service = { id = service_def.id },
      enabled = true,
      name = "basic-auth",
      config = {
        hide_credentials = true,
      }
    }

    before_each(function()
      db.plugins:truncate()
      db.routes:truncate()
      db.services:truncate()
      db.basicauth_credentials:truncate()
      db.consumers:truncate()

      assert(declarative.load_into_db({
        routes = { [route_def.id] = route_def },
        services = { [service_def.id] = service_def },
        consumers = { [consumer_def.id] = consumer_def },
        plugins = { [plugin_def.id] = plugin_def },
        basicauth_credentials = { [basicauth_credential_def.id] = basicauth_credential_def },
      }))
    end)

    describe("load_into_db", function()
      it("imports base and custom entities with associations", function()
        local service = assert(db.services:select_by_name("foo"))
        assert.equals(service_def.id, service.id)
        assert.equals(helpers.mock_upstream_hostname, service.host)
        assert.equals("http", service.protocol)

        local route = assert(db.routes:select_by_name("bar"))
        assert.equals(route_def.id, route.id)
        assert.equals("/", route.paths[1])
        assert.same({ "http" }, route.protocols)
        assert.equals(service_def.id, route.service.id)

        local consumer = assert(db.consumers:select_by_username("andru"))
        assert.equals(consumer_def.id, consumer.id)
        assert.equals("andru", consumer_def.username)
        assert.equals("donalds", consumer_def.custom_id)

        local plugin = assert(db.plugins:select({ id = plugin_def.id }))
        assert.equals(plugin_def.id, plugin.id)
        assert.equals(service.id, plugin.service.id)
        assert.equals("basic-auth", plugin.name)
        assert.same(plugin_def.config, plugin.config)

        local basicauth_credential = assert(db.basicauth_credentials:select({ id = basicauth_credential_def.id }))
        assert.equals(basicauth_credential_def.id, basicauth_credential.id)
        assert.equals(consumer.id, basicauth_credential.consumer.id)
        assert.equals("james", basicauth_credential.username)
        assert.equals(crypto.hash(consumer.id, "secret"), basicauth_credential.password)
      end)
    end)

    describe("access", function()
      local proxy_client

      lazy_setup(function()
        assert(helpers.start_kong({
          nginx_conf = "spec/fixtures/custom_nginx.template",
          database = strategy,
        }))

        proxy_client = helpers.proxy_client()
      end)


      lazy_teardown(function()
        if proxy_client then
          proxy_client:close()
        end

        assert(helpers.stop_kong())
      end)

      describe("Unauthorized", function()
        it("returns 401 Unauthorized on invalid credentials in Authorization", function()
          local res = assert(proxy_client:get("/status/200", {
            headers = {
              ["Authorization"] = "foobar",
            }
          }))
          local body = assert.res_status(401, res)
          local json = cjson.decode(body)
          assert.same({ message = "Invalid authentication credentials" }, json)
        end)
      end)

      describe("Authorized", function()
        it("returns 401 Unauthorized on invalid credentials in Authorization", function()

          local creds = "Basic " .. ngx.encode_base64(
                          string.format("%s:%s", basicauth_credential_def.username,
                                                 basicauth_credential_def.password))

          local res = assert(proxy_client:get("/status/200", {
            headers = {
              ["Authorization"] = creds,
            }
          }))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(consumer_def.id, json.headers["x-consumer-id"])
          assert.equal(consumer_def.username, json.headers["x-consumer-username"])
          assert.equal(consumer_def.custom_id, json.headers["x-consumer-custom-id"])
          assert.equal(basicauth_credential_def.username, json.headers["x-credential-username"])
        end)
      end)
    end)
  end)
end


