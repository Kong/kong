-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- This test case aims to verify that the final content in the database is correctly
-- generated during the upgrade process from version 3.4 to 3.8 when the `graphql-proxy-cache-advanced`
-- plugin is added and its configuration is missing the Redis attribute.
-- In the previous commit [8760](https://github.com/Kong/kong-ee/pull/8760),
-- adding the plugin did not generate content containing the Redis configuration.
-- Consequently, the migration script should handle the absence of the Redis attribute correctly and avoid errors.
-- This test ensures that during database updates, the lack of the Redis attribute in the old configuration
-- does not result in migration failures, thereby ensuring system stability and backward compatibility.

local cjson = require "cjson"
local uh = require "spec.upgrade_helpers"


if uh.database_type() == 'postgres' then
    describe("graphql-proxy-cache-advanced plugin migration - verify the migration without Redis attributes during the upgrade from 3.4 to 3.8.", function()
        local route1_name = "test1"

        describe("when timeout field was not defined", function()
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
                    path = "/routes/",
                    body = {
                        name  = route1_name,
                        hosts = { "test1.test" },
                    },
                    headers = {
                      ["Content-Type"] = "application/json"
                    },
                })
                assert.res_status(201, res)

                res = assert(admin_client:send {
                    method = "POST",
                    path = "/routes/" .. route1_name .. "/plugins/",
                    body = {
                        name = "graphql-proxy-cache-advanced",
                        config = {
                            strategy = "memory",
                        }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })
                local body = cjson.decode(assert.res_status(201, res))
                assert.equal("graphql-proxy-cache-advanced", body.name)
                assert.equal(nil, body.config.redis)
                admin_client:close()
            end)

            uh.new_after_finish("graphql-proxy-cache-advanced migrations work", function ()
                local admin_client = assert(uh.admin_client())
                local res = assert(admin_client:send {
                    method = "GET",
                    path = "/routes/" .. route1_name .. "/plugins/",
                })
                local body = cjson.decode(assert.res_status(200, res))
                assert.equal(1, #body.data)
                assert.equal("graphql-proxy-cache-advanced", body.data[1].name)
                admin_client:close()
            end)
        end)

    end)
end
