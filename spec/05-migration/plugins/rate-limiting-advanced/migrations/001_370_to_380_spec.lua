-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local uh = require "spec.upgrade_helpers"


if uh.database_type() == 'postgres' then
    describe("rate-limiting-advanced plugin migration - timeout field", function()
        local route1_name = "test1"
        local route2_name = "test2"

        describe("when timeout field was defined", function()
            local timeout = 1234

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
                    }
                })
                assert.res_status(201, res)

                res = assert(admin_client:send {
                    method = "POST",
                    path = "/routes/" .. route1_name .. "/plugins/",
                    body = {
                        name = "rate-limiting-advanced",
                        config = {
                            strategy = "redis",
                            window_size = { 1 },
                            limit = { 10 },
                            sync_rate = 0.1,
                            redis = {
                                host = 'localhost',
                                port = 6379,
                                timeout = 1234
                            },
                        }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })
                local body = cjson.decode(assert.res_status(201, res))
                assert.equal("rate-limiting-advanced", body.name)
                assert.equal(timeout, body.config.redis.timeout)
                assert.equal(ngx.null, body.config.redis.connect_timeout)
                assert.equal(ngx.null, body.config.redis.read_timeout)
                assert.equal(ngx.null, body.config.redis.send_timeout)
                admin_client:close()
            end)

            uh.new_after_finish("has updated rate-limiting-advanced redis configuration - connect,read,send are present", function ()
                local admin_client = assert(uh.admin_client())
                local res = assert(admin_client:send {
                    method = "GET",
                    path = "/routes/" .. route1_name .. "/plugins/",
                })
                local body = cjson.decode(assert.res_status(200, res))
                assert.equal(1, #body.data)
                assert.equal("rate-limiting-advanced", body.data[1].name)
                assert.equal(timeout, body.data[1].config.redis.timeout) -- deprecated field is returned as well
                assert.equal(timeout, body.data[1].config.redis.connect_timeout)
                assert.equal(timeout, body.data[1].config.redis.read_timeout)
                assert.equal(timeout, body.data[1].config.redis.send_timeout)

                admin_client:close()
            end)
        end)

        describe("when granular timeouts field were defined", function()
            local timeout = 1234
            local connect_timeout = 100
            local read_timeout = 101
            local send_timeout = 102

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
                        name  = route2_name,
                        hosts = { "test2.test" },
                    },
                    headers = {
                      ["Content-Type"] = "application/json"
                    }
                })
                assert.res_status(201, res)

                res = assert(admin_client:send {
                    method = "POST",
                    path = "/routes/" .. route2_name .. "/plugins/",
                    body = {
                        name = "rate-limiting-advanced",
                        config = {
                            strategy = "redis",
                            window_size = { 1 },
                            limit = { 10 },
                            sync_rate = 0.1,
                            redis = {
                                host = 'localhost',
                                port = 6379,
                                timeout = timeout,
                                connect_timeout = connect_timeout,
                                read_timeout = read_timeout,
                                send_timeout = send_timeout,
                            },
                        }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })
                local body = cjson.decode(assert.res_status(201, res))
                assert.equal("rate-limiting-advanced", body.name)
                assert.equal(timeout, body.config.redis.timeout)
                assert.equal(connect_timeout, body.config.redis.connect_timeout)
                assert.equal(read_timeout, body.config.redis.read_timeout)
                assert.equal(send_timeout, body.config.redis.send_timeout)
                admin_client:close()
            end)

            uh.new_after_finish("has updated rate-limiting-advanced redis configuration - connect,read,send are present", function ()
                local admin_client = assert(uh.admin_client())
                local res = assert(admin_client:send {
                    method = "GET",
                    path = "/routes/" .. route2_name .. "/plugins/",
                })
                local body = cjson.decode(assert.res_status(200, res))
                assert.equal(1, #body.data)
                assert.equal("rate-limiting-advanced", body.data[1].name)
                assert.equal(connect_timeout, body.data[1].config.redis.timeout) -- deprecated field is returned as well but value from connect_timeout is passed
                assert.equal(connect_timeout, body.data[1].config.redis.connect_timeout)
                assert.equal(read_timeout, body.data[1].config.redis.read_timeout)
                assert.equal(send_timeout, body.data[1].config.redis.send_timeout)

                admin_client:close()
            end)
        end)
    end)
end
