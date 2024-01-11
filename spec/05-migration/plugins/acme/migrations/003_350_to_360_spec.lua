
local cjson = require "cjson"
local uh = require "spec.upgrade_helpers"

if uh.database_type() == 'postgres' then
    describe("acme plugin migration", function()
        lazy_setup(function()
            assert(uh.start_kong())
        end)

        lazy_teardown(function ()
            assert(uh.stop_kong(nil, true))
        end)

        uh.setup(function ()
            local admin_client = assert(uh.admin_client())

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
            assert.equal("acme", body.data[1].name)
            local expected_config = {
                account_email = "test@example.com",
                storage = "redis",
                storage_config = {
                    redis = {
                        host = "localhost",
                        port = 57198,
                        password = "secret",
                        database = 2
                    }
                }
            }

            assert.partial_match(expected_config, body.data[1].config)
            admin_client:close()
        end)
    end)
end
