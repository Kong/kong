-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"
local compare_no_order = require "pl.tablex".compare_no_order

local graphql_server_mock_port = helpers.get_available_port()
local original_db_host = os.getenv("KONG_PG_HOST") or "127.0.0.1"
local original_db_port = os.getenv("KONG_PG_PORT") or 5432

local graphql_mock_query = {
  hello_world = [[
    query {
      hello
    }
  ]],

  user_query = [[
    query ($id:ID!) {
      user(id:$id) {
        id
        name
        email
      }
    }
  ]],

  repo_owner_name = [[
    query ($owner:String! $name:String!){
      repository(owner:$owner, name:$name) {
        name
        forkCount
        description
     }
   }
  ]],

  fetch_recent_repos = [[
    query($repoCount: Int!, $rating: Float!, $category: String!, $isActive: Boolean!, $userId: ID!) {
      user(id: $userId) {
        id
        name
        isActive @include(if: $isActive)
        repositories(last: $repoCount) {
          nodes {
            id
            name
            stars(rating: $rating, category: $category)
          }
        }
      }
    }
  ]],
}

for _, strategy in helpers.each_strategy() do
  describe("degraphql plugin access [#" .. strategy .. "#]", function ()
    local admin_client, proxy_client
    local bp, db, mock

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
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

      local service = assert(bp.services:insert {
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

      assert(db.degraphql_routes:insert {
        service = { id = service.id },
        uri = "/",
        query = graphql_mock_query.hello_world,
      })

      assert(db.degraphql_routes:insert {
        service = { id = service.id },
        uri = "/:owner/:name",
        query = graphql_mock_query.repo_owner_name,
      })

      assert(db.degraphql_routes:insert {
        service = { id = service.id },
        uri = "/fetch_recent_repos",
        query = graphql_mock_query.fetch_recent_repos,
      })

      helpers.start_kong({
        database = strategy,
        plugins = "bundled,degraphql",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      mock:stop()
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

    it("can map a graphql query", function ()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        query   = { hello = "world" },
        headers = {
          ["Host"] = "graphql.test"
        }
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.same(graphql_mock_query.hello_world, json.data.query)
      assert.True(compare_no_order({ hello = "world" }, json.data.variables))

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/test/abc",
        headers = {
          ["Host"] = "graphql.test"
        }
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.same(graphql_mock_query.repo_owner_name, json.data.query)
      assert.True(compare_no_order({ owner = "test", name = "abc" }, json.data.variables))


      local ori_graph_query = {
        repoCount = 3, -- A signed 32‐bit integer
        rating = 4.5, -- A signed double-precision floating-point value.
        category = "technology", -- A UTF‐8 character sequence.
        isActive = true, -- true or false.
        userId = "12345" -- ID type, serialized as a String
      }

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/fetch_recent_repos",
        query   = ori_graph_query,
        headers = {
          ["Host"] = "graphql.test"
        }
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.same(ori_graph_query, json.data.variables)
    end)

    it("can update graphql router when creating new graphql_route entity", function ()
      local res = assert(admin_client:send {
        method  = "POST",
        path    = "/services/graphql/degraphql/routes",
        body    = {
          uri = "/user/:id",
          query = graphql_mock_query.user_query,
        },
        headers = {
          ["Content-Type"] = "application/json",
        }
      })

      assert.response(res).has.status(201)

      helpers.wait_for_all_config_update({
        disable_ipv6 = true,
      })

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/user/123",
        headers = {
          ["Host"] = "graphql.test"
        }
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.same(graphql_mock_query.user_query, json.data.query)
      assert.True(compare_no_order({ id = "123" }, json.data.variables))
    end)
  end)

  if strategy == "postgres" then
    describe("degraphql plugin #regression", function ()
      local db_proxy_port = helpers.get_available_port()
      local api_server_port = helpers.get_available_port()
      local trigger_server_port = helpers.get_available_port()

      local bp, db, mock

      lazy_setup(function ()
        local fixtures = {
          http_mock = {
            delay_trigger = [[
              server {
                error_log logs/error.log;
                listen 127.0.0.1:%s;
                location /delay {
                  content_by_lua_block {
                    local sock = ngx.socket.tcp()
                    sock:settimeout(3000)
                    local ok, err = sock:connect('127.0.0.1', '%s')
                    if ok then
                      sock:send("123")
                      ngx.say("ok")
                    else
                      ngx.exit(ngx.ERROR)
                    end
                  }
                }
              }
            ]],
          },

          stream_mock = {
            db_proxy = [[
              server {
                listen %s;
                error_log logs/proxy.log debug;

                content_by_lua_block {
                  local function sleep(n)
                    local t0 = os.clock()
                    while os.clock() - t0 <= n do end
                  end
                  sleep(delay or 0)
                }

                proxy_pass %s:%s;
              }

              # trigger to increase the delay
              server {
                listen %s;
                error_log logs/proxy.log debug;
                content_by_lua_block {
                  if not _G.delay then
                    _G.delay = 10
                  elseif _G.delay and _G.delay == 0 then
                    _G.delay = 10
                  else
                    _G.delay = 0
                  end

                  local sock = assert(ngx.req.socket())
                  local data = sock:receive()

                  if ngx.var.protocol == "TCP" then
                    ngx.say(10)
                  else
                    ngx.send(data)
                  end
                }
              }
            ]],
          },
        }

        fixtures.http_mock.delay_trigger = string.format(
          fixtures.http_mock.delay_trigger, api_server_port, trigger_server_port)

        fixtures.stream_mock.db_proxy = string.format(
          fixtures.stream_mock.db_proxy, db_proxy_port, original_db_host, original_db_port, trigger_server_port)

        assert(helpers.start_kong({
          prefix = "servroot2",
          database = "off",
          admin_listen = "off",
          proxy_listen = "0.0.0.0:" .. helpers.get_available_port(), -- not used
          nginx_conf = "spec/fixtures/custom_nginx.template",
          stream_listen = "0.0.0.0:" .. helpers.get_available_port(), -- not used but for triggering stream template render
        }, nil, nil, fixtures))

        bp, db = helpers.get_db_utils(strategy, {
          "routes",
          "services",
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

        local service = assert(bp.services:insert {
          name = "graphql",
          url = "http://localhost:" .. graphql_server_mock_port,
        })

        assert(bp.routes:insert {
          service = service,
          hosts = { "graphql.test" },
          paths = { "/" },
        })

        assert(db.degraphql_routes:insert {
          service = { name = "graphql" },
          uri = "/",
          query = graphql_mock_query.hello_world,
        })

        assert(helpers.start_kong({
          prefix = "servroot1",
          database = "postgres",
          pg_host = "0.0.0.0",
          pg_port = db_proxy_port,
          pg_timeout = 3000,
          plugins = "bundled,degraphql",
          stream_listen = "off",
        }))
      end)

      lazy_teardown(function ()
        helpers.stop_kong("servroot1")
        helpers.stop_kong("servroot2")
        mock:stop()
      end)

      it("will rebuild route when db delay recover or degraphql route update", function ()
        local admin_client = helpers.admin_client()

        -- Creating degraphql plugin
        local res = assert(admin_client:send {
          method = "POST",
          path = "/services/graphql/plugins",
          body = {
            name = "degraphql",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        assert.res_status(201, res)

        helpers.wait_for_all_config_update({
          disable_ipv6 = true,
        })

        -- Degraphql router should be nil now, triggering delay
        local timeout, force_ip = 3000, "127.0.0.1"
        local delay_proxy_client = helpers.proxy_client(timeout, api_server_port, force_ip)
        local res = delay_proxy_client:get("/delay")
        local body = assert.res_status(200, res)
        assert(body == "ok")
        delay_proxy_client:close()

        local graphql_proxy_client = helpers.proxy_client()

        assert(db.degraphql_routes:insert {
          service = { name = "graphql" },
          uri = "/:owner/:name",
          query = graphql_mock_query.repo_owner_name,
        })

        local res = assert(graphql_proxy_client:send {
          method = "GET",
          path = "/test/123",
          headers = {
            ["Host"] = "graphql.test"
          }
        })

        assert.res_status(404, res)

        -- Flip to no delay
        local timeout, force_ip = 3000, "127.0.0.1"
        local delay_proxy_client = helpers.proxy_client(timeout, api_server_port, force_ip)
        local res = delay_proxy_client:get("/delay")
        local body = assert.res_status(200, res)
        assert(body == "ok")
        delay_proxy_client:close()

        -- Create degraphql route and expect router rebuild
        local admin_client = helpers.admin_client()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/services/graphql/degraphql/routes",
          body = {
            uri = "/user/:id",
            query = graphql_mock_query.user_query,
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)
        admin_client:close()

        helpers.wait_for_all_config_update({
          disable_ipv6 = true,
        })

        local res = assert(graphql_proxy_client:send {
          method = "GET",
          path = "/test/123",
          headers = {
            ["Host"] = "graphql.test"
          }
        })
        assert.res_status(200, res)
        local json = assert.response(res).has.jsonbody()
        assert.same(graphql_mock_query.repo_owner_name, json.data.query)

        local res = assert(graphql_proxy_client:send {
          method = "GET",
          path = "/user/123",
          headers = {
            ["Host"] = "graphql.test"
          }
        })

        assert.res_status(200, res)
        local json = assert.response(res).has.jsonbody()
        assert.same(graphql_mock_query.user_query, json.data.query)
        assert.True(compare_no_order({ id = "123" }, json.data.variables))
        end)
    end)
  end
end
