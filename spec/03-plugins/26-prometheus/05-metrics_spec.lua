local helpers = require "spec.helpers"

describe("Plugin: prometheus (metrics)", function()
    local admin_client

    setup(function()
        bp = helpers.get_db_utils()

        bp.plugins:insert{
            name = "prometheus",
        }

        assert(helpers.start_kong({
            nginx_conf = "spec/fixtures/custom_nginx.template",
            plugins = "bundled,prometheus",
        }))

        admin_client = helpers.admin_client()
    end)

    teardown(function()
        if admin_client then
            admin_client:close()
        end

        helpers.stop_kong()
    end)

    it("expose Nginx connection metrics", function()
        local res = assert(admin_client:send {
            method = "GET",
            path   = "/metrics",
        })
        local body = assert.res_status(200, res)

        assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
        assert.matches('kong_nginx_http_current_connections{state="%w+"} %d+', body)
    end)
end)