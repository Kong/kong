-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local fixtures = require "spec.fixtures.graphql-rl-fixtures"

for _, db_strategy in helpers.each_strategy() do
    describe("graphql-rate-limiting-advanced access with strategy #" .. db_strategy, function()
        local client, admin_client

        setup(function()
            local bp = helpers.get_db_utils(db_strategy, nil, {"graphql-rate-limiting-advanced"})

            local service = bp.services:insert({
                protocol = "https",
                host = "graphql.service.local.domain",
                port = 10002,
                path = "/graphql",
            })

            local route1 = assert(bp.routes:insert {
                hosts = { "route-1.com" },
                service = service,
            })

            assert(bp.plugins:insert {
                name = "graphql-rate-limiting-advanced",
                route = { id = route1.id },
                config = {
                    window_size = {30},
                    sync_rate = -1,
                    limit = {5},
                },
            })

            assert(helpers.start_kong({
                database = db_strategy,
                plugins = "bundled,graphql-rate-limiting-advanced",
                nginx_conf = "spec/fixtures/custom_nginx.template",
            }, nil, nil, fixtures))
        end)

        before_each(function()
            if client then
                client:close()
            end
            if admin_client then
                admin_client:close()
            end
            client = helpers.proxy_client()
            admin_client = helpers.admin_client()
        end)

        teardown(function()
            if client then
                client:close()
            end

            if admin_client then
                admin_client:close()
            end

            helpers.stop_kong(nil, true)
        end)

        it("handles a simple request successfully", function()
            local res = assert(client:send {
                method = "POST",
                path = "/request",
                headers = {
                    ["Host"] = "route-1.com",
                    ["Content-Type"] = "application/x-www-form-urlencoded",
                },
                body = {
                    query = '{ user(id:"1") { id, name }}'
                }
            })

            assert.res_status(200, res)
        end)

    end)
end
