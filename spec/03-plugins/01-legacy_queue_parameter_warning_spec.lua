local cjson      = require "cjson"
local helpers    = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("legacy queue parameters [#" .. strategy .. "]", function()
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
      ["http-log"] = {
        http_endpoint = "http://example.com/",
      },
      ["statsd"] = {},
      ["datadog"] = {},
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
        it("no unexpected queue parameter deprecation warnings by default", function()
          create_plugin()
          assert.logfile().has.no.line("no longer works, please use config.queue", true, log_wait_time)
          assert.logfile().has.no.line("is deprecated, please use config.queue", true, log_wait_time)
        end)

        local parameters = {
          retry_count = 10, -- treated specially below
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
          local expected_warning
          if parameter == "retry_count" then
            expected_warning = "config.retry_count no longer works, please use config.queue."
          else
            expected_warning = "config." .. parameter .. " is deprecated, please use config.queue."
          end
          it ("does not warn when " .. parameter .. " is set to the old default " .. tostring(default_value), function()
            create_plugin(parameter, default_value)
            assert.logfile().has.no.line(expected_warning, true, log_wait_time)
          end)

          it ("does warn when " .. parameter .. " is set to a value different from the old default " .. tostring(default_value), function()
            create_plugin(parameter, default_value + 1)
            assert.logfile().has.line(expected_warning, true, log_wait_time)
          end)
        end
      end)
    end
  end)
end
