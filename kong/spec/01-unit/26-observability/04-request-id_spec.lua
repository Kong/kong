local function reload_module(name)
  package.loaded[name] = nil
  return require(name)
end


local function reset_globals(id)
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
  local ngx_var_request_id = "1234"

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
      reset_globals(ngx_var_request_id)
    end)

    lazy_teardown(function()
      _G.ngx.ctx = old_ngx_ctx
      _G.ngx.var = old_ngx_var
      _G.ngx.get_phase = old_ngx_get_phase
    end)

    it("returns the expected Request ID and caches it in ctx", function()

      local request_id = reload_module("kong.observability.tracing.request_id")

      local id, err = request_id.get()
      assert.is_nil(err)
      assert.equal(ngx_var_request_id, id)

      local ctx_request_id = request_id._get_ctx_request_id()
      assert.equal(ngx_var_request_id, ctx_request_id)
    end)

    it("fails if accessed from phase that cannot read ngx.var", function()
      _G.ngx.get_phase = function() return "init" end

      local request_id = reload_module("kong.observability.tracing.request_id")

      local id, err = request_id.get()
      assert.is_nil(id)
      assert.equal("cannot access ngx.var in init phase", err)
    end)
  end)
end)
