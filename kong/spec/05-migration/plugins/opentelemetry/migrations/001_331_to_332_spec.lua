
local cjson = require "cjson"
local uh = require "spec.upgrade_helpers"


if uh.database_type() == 'postgres' then
    local handler = uh.get_busted_handler("3.0.0", "3.2.0")
    handler("opentelemetry plugin migration", function()
        lazy_setup(function()
            assert(uh.start_kong())
        end)

        lazy_teardown(function ()
            assert(uh.stop_kong())
        end)

        uh.setup(function ()
            local admin_client = assert(uh.admin_client())

            local res = assert(admin_client:send {
                method = "POST",
                path = "/plugins/",
                body = {
                    name = "opentelemetry",
                    config = {
                        endpoint = "http://localhost:8080/v1/traces",
                    }
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })
            assert.res_status(201, res)
            admin_client:close()
        end)

        uh.new_after_finish("has opentelemetry queue configuration", function ()
            local admin_client = assert(uh.admin_client())
            local res = assert(admin_client:send {
                method = "GET",
                path = "/plugins/"
            })
            local body = cjson.decode(assert.res_status(200, res))
            assert.equal(1, #body.data)
            assert.equal("opentelemetry", body.data[1].name)
            local expected_config = {
                queue = {
                    max_batch_size = 200
                },
            }
            assert.partial_match(expected_config, body.data[1].config)
            admin_client:close()
        end)
    end)

    handler = uh.get_busted_handler("3.3.0", "3.6.0")
    handler("opentelemetry plugin migration", function()
        lazy_setup(function()
            assert(uh.start_kong())
        end)

        lazy_teardown(function ()
            assert(uh.stop_kong())
        end)

        uh.setup(function ()
            local admin_client = assert(uh.admin_client())

            local res = assert(admin_client:send {
                method = "POST",
                path = "/plugins/",
                body = {
                    name = "opentelemetry",
                    config = {
                        endpoint = "http://localhost:8080/v1/traces",
                    }
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            -- assert that value of old default is 1
            assert.equals(json.config.queue.max_batch_size, 1)
            admin_client:close()
        end)

        uh.new_after_finish("has updated opentelemetry queue max_batch_size configuration", function ()
            local admin_client = assert(uh.admin_client())
            local res = assert(admin_client:send {
                method = "GET",
                path = "/plugins/"
            })
            local body = cjson.decode(assert.res_status(200, res))
            assert.equal(1, #body.data)
            assert.equal("opentelemetry", body.data[1].name)
            local expected_config = {
                queue = {
                    max_batch_size = 200
                },
            }
            assert.partial_match(expected_config, body.data[1].config)
            admin_client:close()
        end)
    end)
end
