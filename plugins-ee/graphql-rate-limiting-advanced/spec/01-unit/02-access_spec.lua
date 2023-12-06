-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local fixtures = require "spec.fixtures.graphql-rl-fixtures"

-- all_strategries is not available on earlier versions spec.helpers in Kong
local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, db_strategy in strategies() do
    describe("graphql-rate-limiting-advanced access with strategy #" .. db_strategy, function()
        local client

        setup(function()
            local bp = helpers.get_db_utils(db_strategy == "off" and "postgres" or db_strategy,
                                            nil, {"graphql-rate-limiting-advanced"})

            local service = bp.services:insert({
                protocol = "https",
                host = "graphql.service.local.domain",
                port = 10002,
                path = "/graphql",
            })

            if db_strategy ~= "off" then
              local route1 = assert(bp.routes:insert {
                hosts = { "route-1.test" },
                service = service,
              })

              assert(bp.plugins:insert {
                name = "graphql-rate-limiting-advanced",
                route = { id = route1.id },
                config = {
                    window_size = {30},
                    limit = {5},
                    strategy = "cluster",
                    sync_rate = 1,
                },
              })
            end

            local yaml_file = helpers.make_yaml_file([[
              _format_version: '3.0'
              services:
              - name: gql-rl-srv
                url: https://graphql.service.local.domain:10002/graphql
                routes:
                - name: gql-rl-rt
                  hosts:
                  - route-2.test
                  paths:
                  - /request
                  plugins:
                  - name: graphql-rate-limiting-advanced
                    config:
                      window_size:
                      - 30
                      limit:
                      - 5
                      strategy: cluster
                      sync_rate: -1
            ]])

            assert(helpers.start_kong({
                database = db_strategy,
                plugins = "bundled,graphql-rate-limiting-advanced",
                nginx_conf = "spec/fixtures/custom_nginx.template",
                declarative_config = db_strategy == "off" and yaml_file or nil,
                pg_host = db_strategy == "off" and "unknownhost.konghq.test" or nil,
            }, nil, nil, fixtures))
        end)

        before_each(function()
            if client then
                client:close()
            end
            client = helpers.proxy_client()
        end)

        teardown(function()
            if client then
                client:close()
            end

            helpers.stop_kong(nil, true)
        end)

        if db_strategy ~= "off" then
          it("handles a simple request successfully", function()
            local res = assert(client:send {
                method = "POST",
                path = "/request",
                headers = {
                    ["Host"] = "route-1.test",
                    ["Content-Type"] = "application/x-www-form-urlencoded",
                },
                body = {
                    query = '{ user(id:"1") { id, friends }}'
                }
            })

            assert.res_status(200, res)
          end)

        else
          it("handles a simple request successfully in without database", function()
            local res = assert(client:send {
                method = "POST",
                path = "/request",
                headers = {
                    ["Host"] = "route-2.test",
                    ["Content-Type"] = "application/x-www-form-urlencoded",
                },
                body = {
                    query = '{ user(id:"1") { id, friends }}'
                }
            })

            assert.res_status(200, res)
          end)
        end
    end)

    describe("graphql-rate-limiting-advanced with upstream access with strategy #" .. db_strategy, function()
      local client

      setup(function()
          local bp = helpers.get_db_utils(db_strategy == "off" and "postgres" or db_strategy,
                                          nil, {"graphql-rate-limiting-advanced"})

          local upstream = bp.upstreams:insert()

          bp.targets:insert({
            upstream = upstream,
            target = "graphql.service.local.domain:10002",
          })

          local service = bp.services:insert({
            url = "https://" .. upstream.name .. ":10002/graphql",
        })

          if db_strategy ~= "off" then
            local route1 = assert(bp.routes:insert {
              hosts = { "route-1.test" },
              service = service,
            })

            assert(bp.plugins:insert {
              name = "graphql-rate-limiting-advanced",
              route = { id = route1.id },
              config = {
                  window_size = {30},
                  limit = {5},
                  strategy = "cluster",
                  sync_rate = 1,
              },
            })
          end

          local yaml_file = helpers.make_yaml_file([[
            _format_version: '3.0'
            upstreams:
            - name: gql-rl-upstream
              targets:
              - target: graphql.service.local.domain:10002
                weight: 1
            services:
            - name: gql-rl-srv
              url: https://gql-rl-upstream:10002/graphql
              routes:
              - name: gql-rl-rt
                hosts:
                - route-2.test
                paths:
                - /request
                plugins:
                - name: graphql-rate-limiting-advanced
                  config:
                    window_size:
                    - 30
                    limit:
                    - 5
                    strategy: cluster
                    sync_rate: -1
          ]])

          assert(helpers.start_kong({
              database = db_strategy,
              plugins = "bundled,graphql-rate-limiting-advanced",
              nginx_conf = "spec/fixtures/custom_nginx.template",
              declarative_config = db_strategy == "off" and yaml_file or nil,
              pg_host = db_strategy == "off" and "unknownhost.konghq.test" or nil,
          }, nil, nil, fixtures))
      end)

      before_each(function()
          if client then
              client:close()
          end
          client = helpers.proxy_client()
      end)

      teardown(function()
          if client then
              client:close()
          end

          helpers.stop_kong(nil, true)
      end)

      if db_strategy ~= "off" then
        it("handles a simple request successfully", function()
          local res = assert(client:send {
              method = "POST",
              path = "/request",
              headers = {
                  ["Host"] = "route-1.test",
                  ["Content-Type"] = "application/x-www-form-urlencoded",
              },
              body = {
                  query = '{ user(id:"1") { id, friends }}'
              }
          })

          assert.res_status(200, res)
        end)

      else
        it("handles a simple request successfully in without database", function()
          local res = assert(client:send {
              method = "POST",
              path = "/request",
              headers = {
                  ["Host"] = "route-2.test",
                  ["Content-Type"] = "application/x-www-form-urlencoded",
              },
              body = {
                  query = '{ user(id:"1") { id, friends }}'
              }
          })

          assert.res_status(200, res)
        end)
      end
  end)
end
