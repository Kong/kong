-- this software is copyright kong inc. and its licensors.
-- use of the software is subject to the agreement between your organization
-- and kong inc. if there is no such agreement, use is governed by and
-- subject to the terms of the kong master software license agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ end of license 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local insert = table.insert
local factories = require "spec-ee.fixtures.factories.plugins"
local fmt = string.format

local PluginFactory = factories.PluginFactory
local EntitiesFactory = factories.EntitiesFactory

-- the `off` strategy only works when the `postgres` strategy was run before.
for _, strategy in helpers.all_strategies({"postgres", "off"}) do

    describe("Plugins Iterator - Single Scoping - #multiple #ConsumerGroup on #" .. strategy, function()
        local proxy_client, expected_header, must_not_have_headers, unexpected_header

        lazy_teardown(function()
            helpers.stop_kong()
            helpers.kill_all()
            assert(conf_loader(nil, {}))
        end)

        local declarative_config
        lazy_setup(function()
            proxy_client = helpers.proxy_client
            helpers.stop_kong()
            helpers.kill_all()
            assert(conf_loader(nil, {}))

            local ef = EntitiesFactory:setup("postgres")
            local pf = PluginFactory:setup(ef)

            -- adding header-names of plugins that should _not_ be executed
            -- this assists with tracking if a plugin was executed or not
            must_not_have_headers = {}


            expected_header, unexpected_header = pf:consumer_group_multiple_groups()

            insert(must_not_have_headers, unexpected_header)


            insert(must_not_have_headers, pf:route())

            insert(must_not_have_headers, pf:service())

            insert(must_not_have_headers, pf:consumer())

            insert(must_not_have_headers, pf:global())

            assert.is_equal(#must_not_have_headers, 5)

            declarative_config = strategy == "off" and helpers.make_yaml_file() or nil
            assert(helpers.start_kong({
                declarative_config = declarative_config,
                database = strategy ~= "off" and strategy or nil,
                nginx_conf = "spec/fixtures/custom_nginx.template",
            }))
        end)

        it("verify deterministic outcome when dealing with multiple consumergroup affiliation", function()
          for _ = 1, 100 do
            local r = proxy_client():get("/anything", {
                headers = {
                    host = "route.test",
                    -- authenticate as `eve`
                    apikey = "eve",
                },
            })
            assert.response(r).has.status(200)
            -- verify that the expected plugin was executed
            assert.request(r).has_header(expected_header)
            -- verify that no other plugin was executed that had lesser scopes configured
            for _, header in pairs(must_not_have_headers) do
                assert.request(r).has_no_header(header)
            end
          end
        end)
    end)

    describe("Plugins Iterator - #test - #multiple #ConsumerGroup on #", function ()
        local proxy_client

        lazy_teardown(function()
            helpers.stop_kong()
            helpers.kill_all()
            assert(conf_loader(nil, {}))
        end)

        local declarative_config
        lazy_setup(function()
            proxy_client = helpers.proxy_client
            helpers.stop_kong()
            helpers.kill_all()
            assert(conf_loader(nil, {}))

            local bp, db = helpers.get_db_utils("postgres", {
              "consumers",
              "consumer_groups",
              "consumer_group_consumers",
            }, {
              "rate-limiting-advanced",
              "request-transformer-advanced"
            })
            _G.kong.db = db

            local c1 = assert(bp.consumers:insert {
              username = "c1",
            })

            local g1 = assert(bp.consumer_groups:insert {
              name = "g1"
            })

            local c2 = assert(bp.consumers:insert {
              username = "c2",
            })

            local g2 = assert(bp.consumer_groups:insert {
              name = "g2"
            })

            local c3 = assert(bp.consumers:insert {
              username = "c3",
            })

            local g3 = assert(bp.consumer_groups:insert {
              name = "g3"
            })
            local c4 = assert(bp.consumers:insert {
              username = "c4",
            })
            local g4 = assert(bp.consumer_groups:insert {
              name = "g4"
            })
            local g5 = assert(bp.consumer_groups:insert {
              name = "g5"
            })

            assert(bp.consumer_group_consumers:insert {
              consumer       = { id = c1.id },
              consumer_group = { id = g1.id },
            })
            assert(bp.consumer_group_consumers:insert {
              consumer       = { id = c2.id },
              consumer_group = { id = g2.id },
            })
            assert(bp.consumer_group_consumers:insert {
              consumer       = { id = c2.id },
              consumer_group = { id = g1.id },
            })
            assert(bp.consumer_group_consumers:insert {
              consumer       = { id = c3.id },
              consumer_group = { id = g3.id },
            })
            assert(bp.consumer_group_consumers:insert {
              consumer       = { id = c4.id },
              consumer_group = { id = g4.id },
            })
            assert(bp.consumer_group_consumers:insert {
              consumer       = { id = c4.id },
              consumer_group = { id = g5.id },
            })

            bp.keyauth_credentials:insert {
              key = "c1",
              consumer = { id = c1.id },
            }
            bp.keyauth_credentials:insert {
              key = "c2",
              consumer = { id = c2.id },
            }
            bp.keyauth_credentials:insert {
              key = "c3",
              consumer = { id = c3.id },
            }
            bp.keyauth_credentials:insert {
              key = "c4",
              consumer = { id = c4.id },
            }

            local route = bp.routes:insert {
              name = "route-1",
              hosts = { "test.com" },
            }

            bp.plugins:insert {
              name = "key-auth",
              route = { id = route.id },
            }
            bp.plugins:insert {
              name = "request-transformer-advanced",
              consumer_group = { id = g2.id },
              config = {
                add = {
                  headers = {
                    fmt("X-Test-Group:%s", g2.name)
                  }
                }
              }
            }
            bp.plugins:insert {
              name = "request-transformer-advanced",
              route = { id = route.id },
              config = {
                add = {
                  headers = {
                    fmt("X-Test-Route:%s", route.name)
                  }
                }
              }
            }
            bp.plugins:insert {
              name = "request-transformer-advanced",
              -- Even though `g2` has lower priority than `g1`
              -- we still should not prioritize this plugin over
              -- the plugin that is only scoped to `g1` even if it
              -- has "more" scopes, hence more priority according to the
              -- standard precedence model
              route = { id = route.id },
              consumer_group = { id = g2.id },
              config = {
                add = {
                  headers = {
                    fmt("X-Test-Route-Group:%s:%s", route.name, g2.name)
                  }
                }
              }
            }
            bp.plugins:insert {
              name = "request-transformer-advanced",
              consumer_group = { id = g1.id },
              config = {
                add = {
                  headers = {
                    fmt("X-Test-Group:%s", g1.name)
                  }
                }
              }
            }
            bp.plugins:insert {
              name = "request-transformer-advanced",
              route = { id = route.id },
              consumer_group = { id = g5.id },
              config = {
                add = {
                  headers = {
                    fmt("X-Test-Group:%s", g5.name)
                  }
                }
              }
            }
            bp.plugins:insert {
              name = "request-transformer-advanced",
              consumer_group = { id = g5.id },
              config = {
                add = {
                  headers = {
                    fmt("X-Test-Group:%s", g5.name)
                  }
                }
              }
            }
            -- consumer_groups = { g4, g5 }

            bp.plugins:insert {
              name = "rate-limiting-advanced",
              consumer_group = { id = g2.id },
              config = {
                limit = {100},
                window_size = {100},
                window_type = "fixed"
              }
            }
            --[[

            4 consumers, 4 groups
            -----------

            c1:
              groups:
                - g1
            c2:
              groups:
                - g1
                - g2
            c3:
              groups:
                - g3
            c4:
              groups:
                - g4
                - g5

            4 plugins:
            ----------
            RTA:
              scoped to route1
            RTA:
              scoped to g2
            RTA:
              scoped to route1 and g2
            RTA
              scoped to g1
            RLA:
              scoped to g2
            key-auth:
              global

            -- ]]


            declarative_config = strategy == "off" and helpers.make_yaml_file() or nil
            assert(helpers.start_kong({
                plugins = "bundled,rate-limiting-advanced,request-transformer-advanced",
                declarative_config = declarative_config,
                database = strategy ~= "off" and strategy or nil,
                nginx_conf = "spec/fixtures/custom_nginx.template",
            }))
        end)

        it("only group1 plugins should be executed", function ()
          local r = proxy_client():get("/anything", {
              headers = {
                  host = "test.com",
                  apikey = "c1",
              },
          })
          assert.response(r).has.status(200)
          -- verify that the expected plugin was executed
          local g_header = assert.request(r).has_header("X-Test-Group")
          assert.is_equal(g_header, "g1")
          -- verify that rate-limiting was not executed
          assert.request(r).has_not_header("X-RateLimit-Limit")
        end)

        it("group 1 and group2 plugins should be executed", function ()
          local r = proxy_client():get("/anything", {
              headers = {
                  host = "test.com",
                  apikey = "c2",
              },
          })
          assert.response(r).has.status(200)
          -- verify that the expected plugin was executed
          local g_header = assert.request(r).has_header("X-Test-Route-Group")
          assert.is_equal(g_header, "route-1:g2")
          local rla_header = assert.response(r).has_header("RateLimit-Limit")
          -- This time, expect to see rate-limiting
          assert.is_equal(rla_header, "100")
          assert.response(r).has_not_header("X-Test-Route-Group")
        end)

        it("group 3 plugins should be executed (there are none)", function ()
          local r = proxy_client():get("/anything", {
              headers = {
                  host = "test.com",
                  apikey = "c3",
              },
          })
          assert.response(r).has.status(200)
          -- verify that no plugin was executed
          assert.request(r).has_not_header("X-Test-Group")
          assert.response(r).has_not_header("RateLimit-Limit")
        end)

        it("group 4", function ()
          local r = proxy_client():get("/anything", {
              headers = {
                  host = "test.com",
                  apikey = "c4",
              },
          })
          assert.response(r).has.status(200)
          -- verify that no plugin was executed
          assert.response(r).has_not_header("RateLimit-Limit")
          assert.request(r).has_not_header("X-Test-Route")
          local val = assert.request(r).has_header("X-Test-Group")
          assert.is_equal("g5", val)
        end)
    end)
end
