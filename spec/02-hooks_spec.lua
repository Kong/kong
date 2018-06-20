local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: oauth2-introspection (hooks)", function()
  local client, admin_client
  setup(function()
    helpers.dao:drop_schema()
    helpers.dao:run_migrations()

    assert(helpers.dao.apis:insert {
      name = "introspection-api",
      uris = { "/introspect" },
      upstream_url = "http://mockbin.com"
    })

    local api1 = assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "introspection.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2-introspection",
      api_id = api1.id,
      config = {
        introspection_url = string.format(
                      "http://%s:%s/introspect",
                      helpers.test_conf.proxy_ip,
                      helpers.test_conf.proxy_port),
        authorization_value = "hello",
        ttl = 1
      }
    })

    assert(helpers.dao.consumers:insert {
      username = "bob"
    })

    assert(helpers.start_kong({
      custom_plugins = "introspection-endpoint, oauth2-introspection",
      lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua;/kong-plugin/spec/fixtures/custom_plugins/?.lua;;"
    }))

    client = helpers.proxy_client()
    admin_client = helpers.admin_client()

    local res = assert(admin_client:send {
      method = "POST",
      path = "/apis/introspection-api/plugins/",
      body = {
        name = "introspection-endpoint"
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })
    assert.res_status(201, res)
  end)
  teardown(function()
    if admin_client then admin_client:close() end
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("Consumer", function()
    it("invalidates a consumer by username", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request?access_token=valid_consumer",
          headers = {
            ["Host"] = "introspection.com"
          }
        })

        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("bob", body.headers["x-consumer-username"])
        local consumer_id = body.headers["x-consumer-id"]
        assert.is_string(consumer_id)

        -- Deletes the consumer
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/"..consumer_id,
          headers = {
            ["Host"] = "introspection.com"
          }
        })
        assert.res_status(204, res)

        -- ensure cache is invalidated
        helpers.wait_until(function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_consumer",
            headers = {
              ["Host"] = "introspection.com"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          return body.headers["x-consumer-username"] == nil
        end)
      end)
    end)
end)
