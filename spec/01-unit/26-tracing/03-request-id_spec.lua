-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local request_id = require "kong.tracing.request_id"

local function reset_context(id)
  _G.ngx.ctx = {}
  _G.ngx.var = {
    kong_request_id = id,
  }
  _G.ngx.get_phase = function() -- luacheck: ignore
    return "access"
  end

  _G.kong = {
    log = {
      notice = function() end,
      info = function() end,
    },
  }
end


describe("Request ID unit tests", function()
  local kong_request_id_value = "1234"

  describe("get()", function()
    local old_ngx_ctx
    local old_ngx_var
    local old_ngx_get_phase

    lazy_setup(function()
      old_ngx_ctx = _G.ngx.ctx
      old_ngx_var = _G.ngx.var
      old_ngx_get_phase = _G.ngx.get_phase
    end)

    before_each(function()
      reset_context(kong_request_id_value)
    end)

    lazy_teardown(function()
      _G.ngx.ctx = old_ngx_ctx
      _G.ngx.var = old_ngx_var
      _G.ngx.get_phase = old_ngx_get_phase
    end)

    it("returns the expected Request ID and caches it in ctx", function()
      local request_id_value, err = request_id.get()
      assert.is_nil(err)
      assert.equal(kong_request_id_value, request_id_value)

      local ctx_request_id = request_id._get_ctx_request_id()
      assert.equal(kong_request_id_value, ctx_request_id)
    end)

    it("fails if accessed from phase that cannot read ngx.var", function()
      _G.ngx.get_phase = function() return "init" end

      local request_id_value, err = request_id.get()
      assert.is_nil(request_id_value)
      assert.equal("cannot access ngx.var in init phase", err)
    end)
  end)
end)
