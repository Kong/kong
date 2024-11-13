local helpers = require "spec.helpers"
local cjson = require "cjson"


for _, strategy in helpers.each_strategy() do

describe("Admin API[#" .. strategy .. "]" , function()
local client

    lazy_setup(function()
        helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        client = helpers.admin_client()
    end)

    teardown(function()
        if client then
            client:close()
        end
        helpers.stop_kong()
    end)

    it("/timers", function ()
        local res = assert(client:send {
            method = "GET",
            path = "/timers",
            headers = { ["Content-Type"] = "application/json" }
        })

        local body = assert.res_status(200 , res)
        local json = cjson.decode(body)

        assert(type(json.worker.id) == "number")
        assert(type(json.worker.count) == "number")

        assert(type(json.stats.flamegraph.running) == "string")
        assert(type(json.stats.flamegraph.pending) == "string")
        assert(type(json.stats.flamegraph.elapsed_time) == "string")

        assert(type(json.stats.sys.total) == "number")
        assert(type(json.stats.sys.runs) == "number")
        assert(type(json.stats.sys.running) == "number")
        assert(type(json.stats.sys.pending) == "number")
        assert(type(json.stats.sys.waiting) == "number")

        assert(type(json.stats.timers) == "table")

    end)

end)

end
