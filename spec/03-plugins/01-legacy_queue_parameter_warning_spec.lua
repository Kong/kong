local cjson      = require "cjson"
local helpers    = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("legacy queue parameters [#" .. strategy .. "]", function()
    local db

    lazy_setup(function()
      -- Create a service to make sure that our database is initialized properly.
      local bp
      bp, db = helpers.get_db_utils(strategy, {
        "services",
      })

      bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }
    end)

    local admin_client

    before_each(function()

      helpers.clean_logfile()
      db:truncate()

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end
    end)

    local plugins = {
      ["http-log"] = {
        http_endpoint = "http://example.com/",
      },
      ["statsd"] = {},
      ["datadog"] = {},
      ["opentelemetry"] = {
        endpoint = "http://example.com/",
      },
    }

    for plugin, base_config in pairs(plugins) do
      describe("[#" .. plugin .. "]", function()
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
          helpers.stop_kong(nil, true)
          assert.res_status(201, res)
        end

        it("no unexpected queue parameter deprecation warnings", function()
          create_plugin()
          assert.logfile().has.no.line("no longer works, please use config.queue")
        end)

        local parameters = {
          retry_count = 10,
          queue_size = 1,
          flush_timeout = 2
        }

        if plugin == "opentelemetry" then
          parameters = {
            batch_span_count = 200,
            batch_flush_delay = 3,
          }
        end

        for parameter, default_value in pairs(parameters) do
          it ("does not warn when " .. parameter .. " is set to the old default " .. tostring(default_value), function()
            create_plugin(parameter, default_value)
            assert.logfile().has.no.line(parameter)
            assert.logfile().has.no.line("no longer works, please use config.queue", true)
          end)

          it ("does warn when " .. parameter .. " is set to a value different from the old default " .. tostring(default_value), function()
            create_plugin(parameter, default_value + 1)
            assert.logfile().has.line(parameter)
            assert.logfile().has.line("no longer works, please use config.queue", true)
          end)
        end
      end)
    end
  end)
end
