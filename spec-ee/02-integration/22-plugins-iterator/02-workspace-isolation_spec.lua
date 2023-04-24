-- this software is copyright kong inc. and its licensors.
-- use of the software is subject to the agreement between your organization
-- and kong inc. if there is no such agreement, use is governed by and
-- subject to the terms of the kong master software license agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ end of license 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy({ "postgres" }) do
    describe("Plugins Iterator - workspace isolation - #access phase #" .. strategy, function()
        local proxy_client

        lazy_teardown(function()
            helpers.stop_kong()
        end)

        lazy_setup(function()
            helpers.stop_kong()
            local bp = helpers.get_db_utils(strategy, {
                "routes",
                "services",
                "plugins",
                "workspaces",
            }, { "pre-function", })

            local ds = bp.services:insert()
            bp.routes:insert{
                paths = { "/default" },
                service = ds
            }
            -- assign global plugin to default workspace
            bp.plugins:insert{
                name = "pre-function",
                config = {
                    access = {[[
                        kong.response.set_header("default-header", "true")
                    ]]}}
            }
            local ws1 = assert(bp.workspaces:insert({ name = "ws1" }))
            local s1 = bp.services:insert_ws(nil, ws1)
            bp.routes:insert_ws({
                paths = { "/ws_1" },
                service = s1
            }, ws1)

            local ws2 = assert(bp.workspaces:insert({ name = "ws2" }))
            local s2 = bp.services:insert_ws(nil, ws2)
            bp.routes:insert_ws({
                paths = { "/ws_2" },
                service = s2
            }, ws2)

            -- assign global plugin to workspace 2
            bp.plugins:insert_ws({
                name = "pre-function",
                config = {
                    access = {[[
                        kong.response.set_header("ws2-header", "true")
                    ]]}}
            }, ws2)
            -- assign global plugin to workspace 1
            bp.plugins:insert_ws({
                name = "pre-function",
                config = {
                    access = {[[
                        kong.response.set_header("ws1-header", "true")
                    ]]}}
            }, ws1)

            assert(helpers.start_kong({
                database   = strategy,
                nginx_conf = "spec/fixtures/custom_nginx.template",
            }))
            proxy_client = helpers.proxy_client()
        end)

        it("verify that plugins from workspaces2 and default are untouched", function()
            local r = assert(proxy_client:send {
                path = "/ws_1/request"
            })
            assert.response(r).has.status(200)
            assert.response(r).has_header("ws1-header")
            assert.response(r).has_not_header("ws2-header")
            assert.response(r).has_not_header("default-header")
        end)

        it("verify that plugins from workspaces1 and default are untouched", function()
            local r = assert(proxy_client:send {
                path = "/ws_2/request"
            })
            assert.response(r).has.status(200)
            assert.response(r).has_header("ws2-header")
            assert.response(r).has_not_header("ws1-header")
            assert.response(r).has_not_header("default-header")
        end)
    end)

    describe("Plugins Iterator - workspace isolation #non-collecting phases #" .. strategy, function()
        local proxy_client

        lazy_teardown(function()
            helpers.stop_kong()
        end)

        lazy_setup(function()
            helpers.stop_kong()
            local bp = helpers.get_db_utils(strategy, {
                "routes",
                "services",
                "plugins",
                "workspaces",
            }, { "pre-function", })

            local ds = bp.services:insert()
            bp.routes:insert{
                paths = { "/default" },
                service = ds
            }
            -- assign global plugin to default workspace
            bp.plugins:insert{
                name = "pre-function",
                config = {
                    header_filter = {[[
                        kong.response.set_header("default-pre-header-filter", "true")
                    ]]},
                    rewrite = {[[
                        kong.response.set_header("default-pre-rewrite", "true")
                    ]]}}
            }
            bp.plugins:insert{
                name = "post-function",
                config = {
                    header_filter = {[[
                        kong.response.set_header("default-post-header-filter", "true")
                    ]]},
                    rewrite = {[[
                        kong.response.set_header("default-post-rewrite", "true")
                    ]]}}
            }
            local ws1 = assert(bp.workspaces:insert({ name = "ws1" }))
            local s1 = bp.services:insert_ws(nil, ws1)
            bp.routes:insert_ws({
                paths = { "/ws_1" },
                service = s1
            }, ws1)

            local ws2 = assert(bp.workspaces:insert({ name = "ws2" }))
            local s2 = bp.services:insert_ws(nil, ws2)
            bp.routes:insert_ws({
                paths = { "/ws_2" },
                service = s2
            }, ws2)

            -- assign global plugin to workspace 2
            assert(bp.plugins:insert_ws({
                name = "pre-function",
                config = {
                    header_filter = {[[
                        kong.response.set_header("ws2-pre-header-filter", "true")
                    ]]},
                    rewrite = {[[
                        kong.response.set_header("ws2-pre-rewrite", "true")
                    ]]}}
            }, ws2))
            assert(bp.plugins:insert_ws({
                name = "post-function",
                config = {
                    header_filter = {[[
                        kong.response.set_header("ws2-post-header-filter", "true")
                    ]]},
                    rewrite = {[[
                        kong.response.set_header("ws2-post-rewrite", "true")
                    ]]}}
            }, ws2))
            -- assign global plugin to workspace 1
            assert(bp.plugins:insert_ws({
                name = "pre-function",
                config = {
                    header_filter = {[[
                        kong.response.set_header("ws1-pre-header-filter", "true")
                    ]]},
                    rewrite = {[[
                        kong.response.set_header("ws1-pre-rewrite", "true")
                    ]]}}
            }, ws1))
            assert(bp.plugins:insert_ws({
                name = "post-function",
                config = {
                    header_filter = {[[
                        kong.response.set_header("ws1-post-header-filter", "true")
                    ]]},
                    rewrite = {[[
                        kong.response.set_header("ws1-post-rewrite", "true")
                    ]]}}
            }, ws1))

            assert(helpers.start_kong({
                database   = strategy,
                nginx_conf = "spec/fixtures/custom_nginx.template",
            }))
            proxy_client = helpers.proxy_client()
        end)

        it("verify current behavior", function()
            --[[
                The current behaviour in the follwoing scenario:
                 * global plugins in the default workspace
                   * running in phases other than "access"
                 * global plugins in WS1
                   * running in phases other than "access"
                 * global plugins in WS2
                   * running in phases other than "access"

                When Kong processes a request targeted to
                a route configured in a non-default workspace
                any plugin that is configured in the _default_ workspace
                and implements any phase that is run _before_ the
                access phase (rewrite, certificate that is)
                will run regardless of its workspace affiliation of the
                request currently processed.
                Once the request-lifecycle reaches the "access" phase
                the workspace affiliation is detected and the request
                proceeeds as normal (no plugins from _default_ will be executed)
            --]]
            local r = assert(proxy_client:send {
                path = "/ws_1/request"
            })
            assert.response(r).has.status(200)
            -- runs plugins from the `default` workspace up until
            -- the `access` phase.
            assert.response(r).has_header("default-post-rewrite")
            assert.response(r).has_header("default-pre-rewrite")

            -- body-filter runs _after_ the access phase and is not executed
            assert.response(r).has_not_header("default-pre-header-filter")
            assert.response(r).has_not_header("default-post-header-filter")

            -- Instead of the configured plugins in this workspace
            -- Kong executed the plugins configured in the `default` workspace.
            assert.response(r).has_not_header("ws1-pre-rewrite")
            assert.response(r).has_not_header("ws1-post-rewrite")

            -- This runs _after_ the access phase where we already
            -- resolved the workspace affilitaion
            assert.response(r).has_header("ws1-pre-header-filter")
            assert.response(r).has_header("ws1-post-header-filter")

            -- Any plugin from a non-default workspace must not be executed
            -- regardless of it's implemted phasese
            assert.response(r).has_not_header("ws2-pre-rewrite")
            assert.response(r).has_not_header("ws2-post-rewrite")
            assert.response(r).has_not_header("ws2-pre-header-filter")
            assert.response(r).has_not_header("ws2-post-header-filter")
        end)
    end)
end
