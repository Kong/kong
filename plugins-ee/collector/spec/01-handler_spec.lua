-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local helpers = require "spec.helpers"
local strategy = "postgres"


describe("Plugin: collector (handler) [#" .. strategy .. "]", function()
  local proxy_client
  local bp
  local workspace1
  local workspace2
  local mock_url = "http://" .. helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port

  local function create_workspace_structure(workspace, with_collector)
    local service = bp.services:insert_ws({ url = mock_url }, workspace)
    bp.routes:insert_ws({ paths = { '/' .. workspace.name }, service = service, name = workspace.name}, workspace)
    if with_collector then
      bp.plugins:insert_ws({
        name = "collector",
        config = { http_endpoint = mock_url .. "/post_log", queue_size = 1 }
      }, workspace)
    end
  end

  lazy_setup(function()
    bp = helpers.get_db_utils(strategy)

    workspace1 = bp.workspaces:insert({ name = "workspace1"})
    workspace2 = bp.workspaces:insert({ name = "workspace2"})

    create_workspace_structure(workspace1, true)
    create_workspace_structure(workspace2, false)

    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "collector"
    }))

  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    proxy_client = helpers.proxy_client()
    local client = helpers.http_client(helpers.mock_upstream_host, helpers.mock_upstream_port)
    client:delete("/reset_log/hars")
    client:close()
  end)

  after_each(function()
    if proxy_client then
      proxy_client:close()
    end
  end)

  local function send_request(workspace, data, query_string)
    data = data or {user = "kong", password="kong"}
    local res = assert(proxy_client:send({
      method = "POST",
      path = '/' .. workspace.name .. "/post_log/collector" .. (query_string or ''),
      headers = { ["Content-Type"] = "application/json" },
      body = cjson.encode(data),
    }))
    assert.res_status(200, res)
  end

  local function sent_requests()
    local client = helpers.http_client(helpers.mock_upstream_host, helpers.mock_upstream_port)
    local res = assert(client:send {
      method = "GET",
      path = "/read_log/hars",
      headers = {
        Accept = "application/json"
      }
    })
    local raw = assert.res_status(200, res)
    return cjson.decode(raw).entries
  end

  it("logs to collector requests from monitored workspace", function()
    for _ = 1,2 do
      send_request(workspace1)
    end

    helpers.wait_until(function()
      local mock_queue = sent_requests()
      if #mock_queue == 2 then
        return true
      end
    end, 3)
  end)

  it("doesn't log to collector requests from NOT monitored workspace", function()
    for _ = 1,10 do
      send_request(workspace2)
    end

    helpers.wait_until(function()
      local mock_queue = sent_requests()
      if #mock_queue == 0 then
        return true
      end
    end, 5)
  end)

  it("doesn't query string data", function()
    local password = "a_very_sensitive_password"
    send_request(workspace1, {}, "?password=" .. password)

    helpers.wait_until(function()
      local mock_queue = sent_requests()
      if #mock_queue == 1 then
        local query_string = mock_queue[1].request.querystring
        assert.are.same(string.rep('x', #password), query_string['password'])
        return true
      end
    end, 5)
  end)

  it("does't send post body", function()
    local data = { body = { user = { id = { id = 'kong', pass = 'strong' } } } }
    send_request(workspace1, data)

    helpers.wait_until(function()
      local mock_queue = sent_requests()
      if #mock_queue == 1 then
        local post = mock_queue[1].request.post_data
        assert.are.same(post, {})
        return true
      end
    end, 5)
  end)
end)
