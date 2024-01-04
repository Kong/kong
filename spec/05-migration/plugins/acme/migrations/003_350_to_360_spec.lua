
local cjson = require "cjson"

local uh = require "spec.upgrade_helpers"

if uh.database_type() == 'postgres' then
    describe("acme plugin migration", function()
        lazy_setup(function()
            -- uh.get_database()
            assert(uh.start_kong())
        end)

        lazy_teardown(function ()
            assert(uh.stop_kong(nil, true))
        end)

        uh.setup(function ()
            local admin_client = assert(uh.admin_client())
            -- local test_res = assert(admin_client:send {
            --     method = "GET",
            --     path = "/schemas/plugins/acme"
            -- })
            -- assert.res_status(200, test_res)
            -- print("test_res = " .. require("inspect")(test_res))


            local res = assert(admin_client:send {
                method = "POST",
                path = "/plugins/",
                body = {
                    name = "acme",
                    config = {
                        account_email = "test@example.com",
                        storage = "redis",
                        storage_config = {
                            redis = {
                                host = "localhost",
                                port = 57198,
                                auth = "secret",
                                database = 2
                            }
                        }
                    }
                },
                headers = {
                ["Content-Type"] = "application/json"
                }
            })
            assert.res_status(201, res)
            admin_client:close()
        end)

        uh.new_after_up("has updated acme redis configuration", function ()
            local admin_client = assert(uh.admin_client())
            local res = assert(admin_client:send {
                method = "GET",
                path = "/plugins/"
            })
            local body = cjson.decode(assert.res_status(200, res))
            assert.equal(1, #body.data)
            local expected_config = {
                account_email = "test@example.com",
                storage = "redis",
                storage_config = {
                    redis ={
                        base = {
                            host = "localhost",
                            port = 57198,
                            auth = "secret",
                            username = "test",
                            ssl = true,
                            ssl_verify = false,
                            database = 2
                        },
                        extra_options = {
                            namespace = "test_prefix",
                            scan_count = 13
                        }
                    }
                }
            }
            assert.same(expected_config, body.data[1].config)
            admin_client:close()
        end)
    end)
end
