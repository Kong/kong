-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local helpers = require "spec.helpers"

describe("remove_sensible_data_from_table", function()
  local handler = require "kong.plugins.collector.handler"
  local conf = { body_parsing_max_depth = 10 }

  describe("when invalid body", function()
    it("handles empty", function()
      assert.are.same({}, handler.remove_sensible_data_from_table(conf, nil))
      assert.are.same({}, handler.remove_sensible_data_from_table(conf, {}))

      local input = [[{}]]
      assert.are.same({}, handler.remove_sensible_data_from_table(conf, cjson.decode(input)))
    end)
  end)

  describe("filters out values and adds type and length", function()
    it("null in array gets ignored", function()
      local input = [[{"significant_nulls":[null,1,null]}]]
      assert.are.same(
        { significant_nulls = { field_type = "array", field_length = 3 } },
        handler.remove_sensible_data_from_table(conf, cjson.decode(input)))
    end)

    it("null in object gets ignored", function()
      local input = [[{"height":{"metres":1.82,"feet":null}}]]
      assert.are.same({
        height = { metres = { field_type = "number" }}
      }, handler.remove_sensible_data_from_table(conf, cjson.decode(input)))
    end)

    it("numbers", function()
      local input = [[{"age":33}]]
      assert.are.same({
        age = { field_type = "number" }
      }, handler.remove_sensible_data_from_table(conf, cjson.decode(input)))
    end)

    it("strings", function()
      local input = [[{"place":"Newquay"}]]
      assert.are.same({
        place = { field_type = "string", field_length = 7 }
      }, handler.remove_sensible_data_from_table(conf, cjson.decode(input)))
    end)

    it("empty array", function()
      local input = [[{"empty_array":[]}]]
      assert.are.same({
        empty_array = {}
      }, handler.remove_sensible_data_from_table(conf, cjson.decode(input)))
    end)
    it("empty object", function()
      local input = [[{"empty_object":{}}]]
      assert.are.same({
        empty_object = {}
      }, handler.remove_sensible_data_from_table(conf, cjson.decode(input)))
    end)

    it("flat array", function()
      local input = [[{"array1":["value1","value2"]}]]
      assert.are.same(
        { array1 = { field_type = "array", field_length = 2 } },
        handler.remove_sensible_data_from_table(conf, cjson.decode(input)))
    end)

  end)
end)



for _, strategy in helpers.each_strategy() do
  describe("Plugin: collector (handler) [#" .. strategy .. "]", function()
    local proxy_client
    local bp
    local workspace1
    local workspace2
    local workspace3
    local mock_url = "http://" .. helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port

    local function create_workspace_structure(workspace, with_collector)
      local service = bp.services:insert_ws({ url = mock_url }, workspace)
      bp.routes:insert_ws({ hosts = { workspace.name }, service = service}, workspace)
      if with_collector then
        bp.plugins:insert_ws({
          name = "collector",
          config = {
            http_endpoint = mock_url .. "/post_log/",
            queue_size = 1,
            body_parsing_max_depth = 5,
          }
        }, workspace)
      end
    end

    lazy_setup(function()
      bp, _ = helpers.get_db_utils(strategy)

      workspace1 = bp.workspaces:insert({ name = "workspace1"})
      workspace2 = bp.workspaces:insert({ name = "workspace2"})
      workspace3 = bp.workspaces:insert({ name = "workspace3"})

      create_workspace_structure(workspace1, true)
      create_workspace_structure(workspace2, false)
      create_workspace_structure(workspace3, true)

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "collector"
      }))

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      local client = helpers.http_client(helpers.mock_upstream_host, helpers.mock_upstream_port)
      client:delete("/reset_log/hars")
      client:close()
    end)

    after_each(function()
    end)

    local function send_request(workspace, data)
      data = data or {user = "kong", password="kong"}
      local res = proxy_client:send({
        method = "POST",
        path = "/post_log/collector",
        headers = { ["Host"] = workspace.name, ["Content-Type"] = "application/json" },
        body = cjson.encode(data),
      })
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
      end, 10)
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

    it("doesn't send user data", function()
      local data = { body = { user = { id = { id = 'kong', pass = 'strong' } } } }
      for _ = 1,2 do
        send_request(workspace1, data)
      end

      helpers.wait_until(function()
        local mock_queue = sent_requests()
        if #mock_queue == 2 then
          local post = mock_queue[1].request.post_data
          local expected_post = {
            body = {
              user = {
                id = {
                  id = { field_type = "string", field_length = 4 },
                  pass = { field_type = "string", field_length = 6 }
                }
              }
            }
          }
          assert.are.same(post, expected_post)
          return true
        end
      end, 5)
    end)

    it("logs to collector empty body requests", function()
      local res = proxy_client:send({
        method = "POST",
        path = "/post_log/collector",
        headers = { ["Host"] = workspace1.name, ["Content-Type"] = "application/json" },
        body = '{}'
      })
      assert.res_status(200, res)

      res = proxy_client:send({
        method = "POST",
        path = "/post_log/collector",
        headers = { ["Host"] = workspace3.name, ["Content-Type"] = "application/json" },
        body = '{}'
      })
      assert.res_status(200, res)
      local mock_queue


      helpers.wait_until(function()
        mock_queue = sent_requests()
        if #mock_queue == 2 then
          return true
        end
      end, 10)
      assert.are.same(#mock_queue, 2)
    end)

  end)
end
