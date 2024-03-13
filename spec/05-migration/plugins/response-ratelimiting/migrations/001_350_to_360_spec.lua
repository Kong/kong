
local cjson = require "cjson"
local uh = require "spec.upgrade_helpers"


if uh.database_type() == 'postgres' then
    describe("rate-limiting plugin migration", function()
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
                    name = "response-ratelimiting",
                    config = {
                        limits = {
                            video = {
                                minute = 200,
                            }
                        },
                        redis_host = "localhost",
                        redis_port = 57198,
                        redis_username = "test",
                        redis_password = "secret",
                        redis_timeout = 1100,
                        redis_database = 2,
                    }
                },
                headers = {
                ["Content-Type"] = "application/json"
                }
            })
            assert.res_status(201, res)
            admin_client:close()
        end)

        uh.new_after_up("has updated rate-limiting redis configuration", function ()
            local admin_client = assert(uh.admin_client())
            local res = assert(admin_client:send {
                method = "GET",
                path = "/plugins/"
            })
            local body = cjson.decode(assert.res_status(200, res))
            assert.equal(1, #body.data)
            assert.equal("response-ratelimiting", body.data[1].name)
            local expected_config = {
                limits = {
                    video = {
                        minute = 200,
                    }
                },
                redis = {
                    host = "localhost",
                    port = 57198,
                    username = "test",
                    password = "secret",
                    timeout = 1100,
                    database = 2,
                }
            }
            assert.partial_match(expected_config, body.data[1].config)
            admin_client:close()
        end)
    end)
end
