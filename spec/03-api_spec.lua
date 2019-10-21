local cjson   = require "cjson"
local helpers = require "spec.helpers"


local fixtures = {
  http_mock = {
    collector = [[
      server {
        server_name collector;
        listen 5000;

        location /service-map {
          content_by_lua_block {
            local cjson = require("cjson")
            local query_args = ngx.req.get_uri_args()
            if query_args.response_code then
              ngx.status = query_args.response_code
            end

            ngx.say(cjson.encode(query_args))
          }
        }

        location /alerts {
          content_by_lua_block {
            local cjson = require("cjson")
            local query_args = ngx.req.get_uri_args()
            if query_args.response_code then
              ngx.status = query_args.response_code
            end

            ngx.say(cjson.encode(query_args))
          }
        }

        location /alerts/config {
          content_by_lua_block {
            local utils = require "kong.tools.utils"
            local cjson = require("cjson")
            local method = ngx.req.get_method()
            local queryless_url = utils.split(ngx.var.request_uri, "?")[1]
            local id = utils.split(queryless_url, "/")[4]
            ngx.req.read_body()

            if method == "POST" then
              ngx.say(ngx.req.get_body_data())
            elseif method == "PATCH" then
              local data = cjson.decode(ngx.req.get_body_data())
              ngx.say(cjson.encode(data))
            elseif method == "GET" and id == nil then
              local rules = {
                {
                  workspace_name = "not_applied",
                  service_id = cjson.null,
                  route_id = cjson.null,
                  severity = "high",
                },
                {
                  workspace_name = cjson.null,
                  service_id = "not_applied",
                  route_id = cjson.null,
                  severity = "low",
                },
                {
                  workspace_name = cjson.null,
                  service_id = cjson.null,
                  route_id = "not_applied",
                  severity = "medium",
                },
                {
                  workspace_name = "workspace1",
                  service_id = cjson.null,
                  route_id = cjson.null,
                  severity = "medium",
                },
                {
                  workspace_name = cjson.null,
                  service_id = cjson.null,
                  route_id = "2f081378-01aa-490d-906e-b382dc78ee01",
                  severity = "low",
                },
              }
              ngx.say(cjson.encode(rules))
            else
              local params = ngx.req.get_uri_args()
              params.id = id
              params.method = method
              ngx.say(cjson.encode(params))
            end
          }
        }

        location /status {
          content_by_lua_block {
            local cjson = require("cjson")
            local query_args = ngx.req.get_uri_args()
            local status = {
              immunity = {
                available = true,
                version = "1.7.1"
              },
              brain = {
                available = true,
                version = "1.7.1"
              }
            }
            if query_args.response_code then
              ngx.status = query_args.response_code
            end

            ngx.say(cjson.encode(status))
          }
        }
      }
    ]]
  },
}


for _, strategy in helpers.each_strategy() do
  describe("Plugin: collector (API) [#" .. strategy .. "]", function()
    local admin_client
    local bp
    local db
    local workspace1
    local workspace2
    local route1

    lazy_setup(function()
      local plugin_config = {
        host = '127.0.0.1',
        port = 5000,
        https = false,
        log_bodies = true,
        queue_size = 1,
        flush_timeout = 1
      }
      bp, db = helpers.get_db_utils(strategy, nil, { "collector" })

      workspace1 = bp.workspaces:insert({ name = "workspace1"})
      workspace2 = bp.workspaces:insert({ name = "workspace2"})

      route1 = bp.routes:insert_ws(
        {
          id = "2f081378-01aa-490d-906e-b382dc78ee01",
          name = "route1",
          paths = { "/ws1" },
        },
        workspace1
      )

      bp.plugins:insert_ws({ name = "collector", config = plugin_config }, workspace1)
      bp.plugins:insert_ws({ name = "collector", config = plugin_config }, workspace2)

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "collector" }, nil, nil, fixtures))
      admin_client = helpers.admin_client()
    end)

    before_each(function()
      db:truncate("service_maps")
    end)

    teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("/service_maps", function()
      describe("GET", function()
        it("forwards query parameters and adds workspace_name", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/workspace2/service_maps?service_id=123"
          })
          local body = assert.res_status(200, res)
          local expected_params = {
            workspace_name = workspace2.name,
            service_id = "123",
          }
          assert.are.same(cjson.decode(body), expected_params)
        end)

        it("returns whatever response code returned by upstream", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/workspace2/service_maps?response_code=300"
          })
          assert.res_status(300, res)
        end)
      end)
    end)

    describe("/collector/alerts", function()
      describe("GET", function()
        it("forwards query parameters and adds workspace_name", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/workspace2/collector/alerts?severity=high&alert_name=traffic"
          })
          local body = assert.res_status(200, res)
          local expected_params = {
            workspace_name = workspace2.name,
            alert_name = "traffic",
            severity = "high"
          }
          assert.are.same(cjson.decode(body), expected_params)
        end)

        it("returns whatever response code returned by upstream", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/workspace2/collector/alerts?severity=high&response_code=300"
          })
          assert.res_status(300, res)
        end)
      end)
    end)

    describe("/collector/alerts/config", function()
      describe("GET", function()
        it("filters workspace's entities", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/workspace1/collector/alerts/config"
          })
          local body = assert.res_status(200, res)
          assert.are.same(cjson.decode(body), {
            {
              workspace_name = "workspace1",
              service_id = cjson.null,
              route_id = cjson.null,
              severity = "medium"
            },
            {
              workspace_name = cjson.null,
              service_id = cjson.null,
              route_id = "2f081378-01aa-490d-906e-b382dc78ee01",
              severity = "low"
            },
          })
        end)
      end)
      describe("POST", function()
        it("forwards post arguments", function()
          local expected_body = {
            route_id = route1.id,
            severity = "high",
            workspace_name = "workspace1",
          }

          local res = assert(admin_client:send {
            method = "POST",
            path = "/workspace1/collector/alerts/config",
            body = expected_body,
            headers = { ["Content-Type"] = "application/json" }
          })

          local body = assert.res_status(200, res)
          assert.are.same(cjson.decode(body), expected_body)
        end)
      end)
    end)

    describe("/collector/alerts/config/{id}", function()
      describe("GET", function()
        it("forwards rule id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/workspace2/collector/alerts/config/20"
          })
          local body = assert.res_status(200, res)
          assert.are.same(cjson.decode(body), { id = "20", method = "GET" })
        end)
      end)
      describe("DELETE", function()
        it("forwards rule id", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path = "/workspace2/collector/alerts/config/20"
          })
          local body = assert.res_status(200, res)
          assert.are.same(cjson.decode(body), { id = "20", method = "DELETE"})
        end)
      end)
      describe("PATCH", function()
        it("forwards post arguments", function()
          local expected_body = {
            id = "20",
            route_id = route1.id,
            severity = "high"
          }

          local res = assert(admin_client:send {
            method = "PATCH",
            path = "/workspace1/collector/alerts/config/20",
            body = { route_id = route1.id, severity = "high" },
            headers = { ["Content-Type"] = "application/json" }
          })

          local body = assert.res_status(200, res)
          assert.are.same(cjson.decode(body), expected_body)
        end)
      end)
    end)

    describe("/collector/status", function()
      describe("GET", function()
        it("returns backend status", function()
          local path = "/workspace2/collector/status"
          local res = assert(admin_client:send({method = "GET", path = path}))
          local body = assert.res_status(200, res)

          local expected_status = {
            immunity = {
              available = true,
              version = "1.7.1"
            },
            brain = {
              available = true,
              version = "1.7.1"
            }
          }
          assert.are.same(cjson.decode(body), expected_status)
        end)
      end)
    end)
  end)
end
