local cjson      = require "cjson"
local helpers    = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("legacy propagation parameters [#" .. strategy .. "]", function()
    local db
    local admin_client

    lazy_setup(function()
      -- Create a service to make sure that our database is initialized properly.
      local bp
      bp, db = helpers.get_db_utils(strategy, {
        "services",
      })

      db:truncate()

      bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }
      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end
      helpers.stop_kong()
    end)

    before_each(function()
      helpers.clean_logfile()
    end)

    local plugin_id

    after_each(function()
      if plugin_id then
        local res = admin_client:delete("/plugins/" .. plugin_id)
        assert.res_status(204, res)
      end
    end)

    local plugins = {
      ["zipkin"] = {
        http_endpoint = "http://example.com/",
      },
      ["opentelemetry"] = {
        traces_endpoint = "http://example.com/",
      },
    }

    for plugin, base_config in pairs(plugins) do

      local function create_plugin(parameter, value)
        local config = table.clone(base_config)
        if parameter then
          config[parameter] = value
        end

        local res = admin_client:post(
          "/plugins",
          {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = cjson.encode({
              name = plugin,
              config = config
            })
          }
        )
        local body = cjson.decode(assert.res_status(201, res))
        plugin_id = body.id
      end

      local log_wait_time = 0.01
      describe("[#" .. plugin .. "]", function()
        it("no unexpected propagation parameter deprecation warnings by default", function()
          create_plugin()
          assert.logfile().has.no.line("is deprecated, please use config.queue", true, log_wait_time)
        end)

        local parameters = { header_type = {
          default_value = "preserve",
          test_values = { "jaeger", "w3c", "ignore" }
        } }

        if plugin == "zipkin" then
          parameters.default_header_type = {
            default_value = "b3",
            test_values = { "ot", "aws", "datadog" }
          }
        end

        for parameter, values in pairs(parameters) do
          local default_value = values.default_value
          local test_values = values.test_values
          local expected_warning = "config." .. parameter .. " is deprecated, please use config.propagation"

          it ("does not warn when " .. parameter .. " is set to the old default " .. tostring(default_value), function()
            create_plugin(parameter, default_value)
            assert.logfile().has.no.line(expected_warning, true, log_wait_time)
          end)

          for _, test_value in ipairs(test_values) do
            it ("does warn when " .. parameter .. " is set to a value different from the old default "
                .. tostring(default_value) .. " (" .. tostring(test_value) .. ")", function()
              create_plugin(parameter, test_value)
              assert.logfile().has.line(expected_warning, true, log_wait_time)
            end)
          end
        end
      end)
    end
  end)
end
