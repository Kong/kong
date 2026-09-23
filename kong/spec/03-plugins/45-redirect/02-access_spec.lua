local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
    describe("Plugin: redirect (access) [#" .. strategy .. "]", function()
        local proxy_client
        local admin_client

        lazy_setup(function()
            local bp = helpers.get_db_utils(strategy, { "routes", "services", "plugins" })

            -- Default status code
            local route1 = bp.routes:insert({
                hosts = { "api1.redirect.test" }
            })

            bp.plugins:insert {
                name = "redirect",
                route = {
                    id = route1.id
                },
                config = {
                    location = "https://example.com"
                }
            }

            -- Custom status code
            local route2 = bp.routes:insert({
                hosts = { "api2.redirect.test" }
            })

            bp.plugins:insert {
                name = "redirect",
                route = {
                    id = route2.id
                },
                config = {
                    status_code = 302,
                    location = "https://example.com"
                }
            }

            -- config.keep_incoming_path = false
            local route3 = bp.routes:insert({
                hosts = { "api3.redirect.test" }
            })

            bp.plugins:insert {
                name = "redirect",
                route = {
                    id = route3.id
                },
                config = {
                    location = "https://example.com/path?foo=bar"
                }
            }

            -- config.keep_incoming_path = true
            local route4 = bp.routes:insert({
                hosts = { "api4.redirect.test" }
            })

            bp.plugins:insert {
                name = "redirect",
                route = {
                    id = route4.id
                },
                config = {
                    location = "https://example.com/some_path?foo=bar",
                    keep_incoming_path = true
                }
            }

            assert(helpers.start_kong({
                database = strategy,
                nginx_conf = "spec/fixtures/custom_nginx.template",
                headers_upstream = "off"
            }))
        end)

        lazy_teardown(function()
            helpers.stop_kong()
        end)

        before_each(function()
            proxy_client = helpers.proxy_client()
            admin_client = helpers.admin_client()
        end)

        after_each(function()
            if proxy_client then
                proxy_client:close()
            end
            if admin_client then
                admin_client:close()
            end
        end)

        describe("status code", function()
            it("default status code", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/status/200",
                    headers = {
                        ["Host"] = "api1.redirect.test"
                    }
                })
                assert.res_status(301, res)
            end)

            it("custom status code", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/status/200",
                    headers = {
                        ["Host"] = "api2.redirect.test"
                    }
                })
                assert.res_status(302, res)
            end)
        end)

        describe("location header", function()
            it("supports path and query params in location", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/status/200",
                    headers = {
                        ["Host"] = "api3.redirect.test"
                    }
                })
                local header = assert.response(res).has.header("location")
                assert.equals("https://example.com/path?foo=bar", header)
            end)

            it("keeps the existing redirect URL", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/status/200?keep=this",
                    headers = {
                        ["Host"] = "api4.redirect.test"
                    }
                })
                local header = assert.response(res).has.header("location")
                assert.equals("https://example.com/status/200?keep=this", header)
            end)
        end)
    end)
end
