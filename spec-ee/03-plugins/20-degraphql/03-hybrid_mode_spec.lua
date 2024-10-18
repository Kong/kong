-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"
local graphql_server_mock_port = helpers.get_available_port()
local compare_no_order = require "pl.tablex".compare_no_order

local graphql_mock_query = {
  hello_world = [[
    query {
      hello
    }
  ]],
}

for _, strategy in helpers.each_strategy() do
  describe("degraphql plugin hybrid mode #" .. strategy, function()
    local admin_client, proxy_client
    local bp, db, mock
    local service, degraphql_route

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "clustering_data_planes",
        "certificates",
        "plugins",
        "consumers",
        "degraphql_routes",
      }, {"degraphql"})

      mock = http_mock.new(graphql_server_mock_port, {
        ["/graphql"] = {
          access = [[
            local cjson = require "cjson"
            ngx.req.read_body()
            local echo = ngx.req.get_body_data()
            ngx.status = 200
            ngx.say('{"data":' .. echo .. '}')
          ]]
        },
      })
      mock:start()

      service = assert(bp.services:insert {
        name = "graphql",
        url = "http://localhost:" .. graphql_server_mock_port,
      })

      assert(bp.routes:insert {
        service = service,
        hosts = { "graphql.test" },
        paths = { "/" },
      })

      assert(bp.plugins:insert {
        name = "degraphql",
        service = { id = service.id },
        config = {
          graphql_server_path = "/graphql",
        },
      })

      degraphql_route = assert(db.degraphql_routes:insert {
        service = { id = service.id },
        uri = "/",
        query = graphql_mock_query.hello_world,
      })

      assert(
        helpers.start_kong({
          role = "control_plane",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          database = strategy,
          prefix = "serve_cp",
          cluster_listen = "127.0.0.1:9005",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          log_level = "info",
        })
      )

      assert(
        helpers.start_kong({
          role = "data_plane",
          database = "off",
          prefix = "serve_dp",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          cluster_control_plane = "127.0.0.1:9005",
          log_level = "info",
        })
      )
    end)

    lazy_teardown(function()
      assert(helpers.stop_kong("serve_cp"))
      assert(helpers.stop_kong("serve_dp"))
      assert(mock:stop())
    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("should delete module-level degraphql_routes on data plane", function()
      helpers.wait_until(function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          query   = { hello = "world" },
          headers = {
            ["Host"] = "graphql.test"
          }
        })

        return pcall(function()
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
          assert.same(graphql_mock_query.hello_world, json.data.query)
          assert.True(compare_no_order({ hello = "world" }, json.data.variables))
        end)
      end)

      local res = assert(admin_client:send {
        method  = "DELETE",
        path    = "/services/" .. service.name .. "/degraphql/routes/" .. degraphql_route.id,
        headers = {
          ["Content-Type"] = "application/json",
        }
      })

      assert.res_status(204, res)

      helpers.wait_until(function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          query   = { hello = "world" },
          headers = {
            ["Host"] = "graphql.test"
          }
        })

        return pcall(function()
          assert.response(res).has.status(404)
        end)
      end)
    end)
  end)
end
