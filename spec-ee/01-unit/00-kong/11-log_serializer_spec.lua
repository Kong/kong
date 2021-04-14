-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local basic = require "kong.plugins.log-serializers.basic"
local utils = require "kong.tools.utils"


describe("Log Serializer", function()
  before_each(function()
    _G.ngx = {
      ctx = {
        balancer_data = {
          tries = {
            {
              ip = "127.0.0.1",
              port = 8000,
            },
          },
        },
      },
      var = {
        request_uri = "/request_uri",
        upstream_uri = "/upstream_uri",
        scheme = "http",
        host = "test.com",
        server_port = 80,
        request_length = 200,
        bytes_sent = 99,
        request_time = 2,
        remote_addr = "1.1.1.1"
      },
      req = {
        get_uri_args = function() return {"arg1", "arg2"} end,
        get_method = function() return "POST" end,
        get_headers = function() return {"header1", "header2"} end,
        start_time = function() return 3 end
      },
      resp = {
        get_headers = function() return {"respheader1", "respheader2"} end
      }
    }

    kong = kong or {}
    package.loaded["kong.pdk.request"] = nil
    local pdk_request = require "kong.pdk.request"
    kong.request = pdk_request.new(kong)
  end)

  describe("Basic", function()
    it("serializes the workspaces information", function()
      local req_workspaces = {{id = utils.uuid(), name = "default"}}
      ngx.ctx.log_request_workspaces = req_workspaces
      local res = basic.serialize(ngx, kong)
      assert.same(req_workspaces,  res.workspaces)
    end)
  end)
end)
