local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local insert = table.insert
local factories = require "spec.fixtures.factories.plugins"

local PluginFactory = factories.PluginFactory
local EntitiesFactory = factories.EntitiesFactory

for _, strategy in helpers.each_strategy() do
  describe("Plugins Iterator - Ensure correctness #" .. strategy, function()
    local proxy_client, expected_header, must_not_have_headers, n_entities

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))
    end)

    lazy_setup(function()
      proxy_client = helpers.proxy_client
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))
      n_entities = 10

      local ef = EntitiesFactory:setup(strategy)
      ef.bp.plugins:insert(
        {
          name = "response-transformer",
          -- scope to default route
          route = { id = ef.route_id },
          config = {
            add = {
              headers = { "response-transformed:true" }
            }
          }
        }
      )
      ef.bp.plugins:insert(
        {
          name = "correlation-id",
          -- scope to default route
          route = { id = ef.route_id },
          config = {
            header_name = "correlation-id-added"
          }
        }
      )

      for i = 0, n_entities do
        local service = ef.bp.services:insert {
          path = "/anything/service-" .. i
        }
        ef.bp.routes:insert {
          hosts = { "route.bar." .. i },
          service = { id = service.id }
        }
        ef.bp.plugins:insert(
          {
            name = "correlation-id",
            service = { id = service.id },
            config = {
              header_name = "correlation-id-added-service" .. i
            }
          }
        )
        ef.bp.plugins:insert(
          {
            name = "response-transformer",
            service = { id = service.id },
            config = {
              add = {
                headers = { "response-transformed-" .. i .. ":true" }
              }
            }
          }
        )
      end

      local pf = PluginFactory:setup(ef)
      -- add a plugin scoped to Consumer, Route and Service
      expected_header = pf:consumer_route_service()
      must_not_have_headers = {}

      -- scoped to Consumer, Route
      insert(must_not_have_headers, (pf:consumer_route()))
      -- assure we don't iterate over #{}
      assert.is_equal(#must_not_have_headers, 1)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    it("ensure no cross-contamination", function()
      -- meaning that we don't run plugins that are scoped to a specific service
      for i = 0, n_entities do
        local r = proxy_client():get("/anything/service-" .. i, {
          headers = {
            host = "route.bar." .. i,
            -- authenticate as `alice`
            apikey = "alice",
          },
        })
        assert.response(r).has.status(200)

        -- The plugin for _THIS_ service is executed
        assert.request(r).has_header("correlation-id-added-service" .. i)
        assert.response(r).has_header("response-transformed-" .. i)
        -- check that no header of any other service is present
        for j = 0, n_entities do
            if j ~= i then
              assert.request(r).has_no_header("correlation-id-added-service"..j)
              assert.response(r).has_no_header("response-transformed-" .. j)
            end
        end
      end
    end)

    it("runs plugins in various phases", function()
      local r = proxy_client():get("/anything", {
        headers = {
          host = "route.test",
          -- authenticate as `alice`
          apikey = "alice",
        },
      })
      assert.response(r).has.status(200)
      -- assert that request-termination was executed
      assert.request(r).has_header(expected_header)
      -- assert that no other `request-transformer` plugin was executed that had lesser scopes configured
      for _, header in pairs(must_not_have_headers) do
        assert.request(r).has_no_header(header)
      end
      -- assert that the `response-transformer` plugin was executed
      assert.response(r).has_header("response-transformed")
      -- assert that the `correlation-id` plugin was executed
      assert.request(r).has_header("correlation-id-added")
    end)
  end)
end
