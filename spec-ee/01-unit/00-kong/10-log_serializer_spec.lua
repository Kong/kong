-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

describe("Log Serializer", function()
  local utils

  before_each(function()
    _G.ngx = setmetatable({
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
        host = "test.test",
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
      },
      status = 200,
    }, { __index = ngx })

    _G.kong = kong or {
      configuration = {}
    }

    package.loaded["kong.pdk.private.phases"] = {
      new = function() end,
      check = function() end,
      phases = {},
    }

    package.loaded["kong.pdk.client"] = nil
    local pdk_client = require "kong.pdk.client"
    kong.client = pdk_client.new(kong)

    package.loaded["kong.pdk.table"] = nil
    local pdk_table = require "kong.pdk.table"
    kong.table = pdk_table.new(kong)

    package.loaded["kong.pdk.ip"] = nil
    local pdk_ip = require "kong.pdk.ip"
    kong.ip = pdk_ip.new(kong)

    package.loaded["kong.pdk.log"] = nil
    local pdk_log = require "kong.pdk.log"
    kong.log = pdk_log.new(kong)

    package.loaded["kong.pdk.request"] = nil
    local pdk_request = require "kong.pdk.request"
    kong.request = pdk_request.new(kong)

    utils = require "kong.tools.utils"
  end)

  describe("Basic", function()
    it("serializes the workspaces information", function()

      local req_workspace = utils.uuid()
      ngx.ctx.workspace = req_workspace
      ngx.ctx.workspace_name = "ws1"
      local res = kong.log.serialize({ngx = ngx, kong = kong, })
      assert.same(req_workspace,  res.workspace)
      assert.same("ws1",res.workspace_name)
    end)
  end)
end)
