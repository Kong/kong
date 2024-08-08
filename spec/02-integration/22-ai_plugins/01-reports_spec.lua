local helpers = require "spec.helpers"
local constants = require "kong.constants"
local cjson = require "cjson"
local pl_file = require "pl.file"

local PLUGIN_NAME = "ai-proxy"
local MOCK_PORT = helpers.get_available_port()

for _, strategy in helpers.each_strategy() do
  local admin_client
  local dns_hostsfile
  local reports_server

  describe("anonymous reports for ai plugins #" .. strategy, function()
    local reports_send_ping = function(port)
      assert.eventually(function()
        admin_client = helpers.admin_client()
        local res = admin_client:post("/reports/send-ping" .. (port and "?port=" .. port or ""))
        assert.response(res).has_status(200)
        admin_client:close()
      end)
      .has_no_error("ping request was sent successfully")
    end

    lazy_setup(function()
      dns_hostsfile = assert(os.tmpname() .. ".hosts")
      local fd = assert(io.open(dns_hostsfile, "w"))
      assert(fd:write("127.0.0.1 " .. constants.REPORTS.ADDRESS))
      assert(fd:close())

      local bp = assert(helpers.get_db_utils(strategy, {
        "services",
        "routes",
        "plugins",
      }, { "reports-api" }))

            -- set up openai mock fixtures
            local fixtures = {
              http_mock = {},
            }

            fixtures.http_mock.openai = [[
              server {
                  server_name openai;
                  listen ]]..MOCK_PORT..[[;

                  default_type 'application/json';


                  location = "/llm/v1/chat/good" {
                    content_by_lua_block {
                      local pl_file = require "pl.file"
                      local json = require("cjson.safe")

                      ngx.req.read_body()
                      local body, err = ngx.req.get_body_data()
                      body, err = json.decode(body)

                      local token = ngx.req.get_headers()["authorization"]
                      local token_query = ngx.req.get_uri_args()["apikey"]

                      if token == "Bearer openai-key" or token_query == "openai-key" or body.apikey == "openai-key" then
                        ngx.req.read_body()
                        local body, err = ngx.req.get_body_data()
                        body, err = json.decode(body)

                        if err or (body.messages == ngx.null) then
                          ngx.status = 400
                          ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
                        else
                          ngx.status = 200
                          ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/good.json"))
                        end
                      else
                        ngx.status = 401
                        ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/unauthorized.json"))
                      end
                    }
                  }
              }
            ]]

      local http_srv = assert(bp.services:insert {
        name = "mock-service",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
      })

      local chat_good = assert(bp.routes:insert {
        service = http_srv,
        protocols = { "http" },
        hosts = { "http-service.test" }
      })

      local chat_good_2 = assert(bp.routes:insert {
        service = http_srv,
        protocols = { "http" },
        hosts = { "http-service.test_2" }
      })

      bp.plugins:insert({
        name = "reports-api",
        config = {}
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good.id },
        config = {
          route_type = "llm/v1/chat",
          logging = {
            log_payloads = false,
            log_statistics = true,
          },
          auth = {
            header_name = "Authorization",
            header_value = "Bearer openai-key",
          },
          model = {
            name = "gpt-3.5-turbo",
            provider = "openai",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good"
            },
          },
        },
      }

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good_2.id },
        config = {
          route_type = "llm/v1/chat",
          logging = {
            log_payloads = false,
            log_statistics = false, -- should work also for statistics disable
          },
          auth = {
            header_name = "Authorization",
            header_value = "Bearer openai-key",
          },
          model = {
            name = "gpt-3.5-turbo",
            provider = "openai",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good"
            },
          },
        },
      }

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = strategy,
        dns_hostsfile = dns_hostsfile,
        resolver_hosts_file = dns_hostsfile,
        plugins = "bundled,reports-api",
        anonymous_reports = true,
      }, nil, nil, fixtures))

    end)

    lazy_teardown(function()
      os.remove(dns_hostsfile)

      helpers.stop_kong()
    end)

    before_each(function()
      reports_server = helpers.tcp_server(constants.REPORTS.STATS_TLS_PORT, {tls=true})
    end)

    describe("check report has ai data", function()
      it("logs correct data for report on a request triggering a ai plugin", function()
        local proxy_client = assert(helpers.proxy_client())
        local res = proxy_client:get("/", {
          headers = { 
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["host"]  = "http-service.test",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
        })
        assert.res_status(200, res)

        reports_send_ping(constants.REPORTS.STATS_TLS_PORT)

        proxy_client:close()

        local _, reports_data = assert(reports_server:join())
        reports_data = cjson.encode(reports_data)

        assert.match("ai_response_tokens=8", reports_data)
        assert.match("ai_prompt_tokens=10", reports_data)
        assert.match("ai_reqs=1", reports_data)
      end)

      it("logs correct data for a different routes triggering a ai plugin", function()
        local proxy_client = assert(helpers.proxy_client())
        local res = proxy_client:get("/", {
          headers = { 
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["host"]  = "http-service.test",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
        })
        assert.res_status(200, res)

        local proxy_client_2 = assert(helpers.proxy_client())
        local res_2 = proxy_client_2:get("/", {
          headers = { 
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["host"]  = "http-service.test_2",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
        })
        assert.res_status(200, res_2)

        reports_send_ping(constants.REPORTS.STATS_TLS_PORT)

        proxy_client:close()
        proxy_client_2:close()

        local _, reports_data = assert(reports_server:join())
        reports_data = cjson.encode(reports_data)

        assert.match("ai_response_tokens=16", reports_data)
        assert.match("ai_prompt_tokens=20", reports_data)
        assert.match("ai_reqs=2", reports_data)
      end)
    end)

  end)
end
