describe("Log Serializer", function()
  local basic, utils

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

    package.loaded["kong.pdk.log"] = nil
    local pdk_log = require "kong.pdk.log"
    kong.log = pdk_log.new(kong)

    package.loaded["kong.pdk.request"] = nil
    local pdk_request = require "kong.pdk.request"
    kong.request = pdk_request.new(kong)

    basic = require "kong.plugins.log-serializers.basic"
    utils = require "kong.tools.utils"
  end)

  describe("Basic", function()
    it("serializes the workspaces information", function()

      local req_workspace = utils.uuid()
      ngx.ctx.workspace = req_workspace
      local res = basic.serialize(ngx, kong)
      assert.same(req_workspace,  res.workspace)
    end)
  end)
end)
