local helpers = require "spec.helpers"
local session = require "kong.plugins.session.session"
local phases = require "kong.pdk.private.phases"

describe("Plugin: Session - session.lua", function()
  local old_ngx

  before_each(function()
    kong.ctx.core.phase = phases.phases.request

    old_ngx = {
      get_phase = function()end,
      req = {
        read_body = function()end
      },
      log = function() end,
      DEBUG = 1
    }
    _G.ngx = old_ngx
  end)

  after_each(function()
    _G.ngx = old_ngx
  end)


  it("logs out with GET request", function()
    kong.request.get_query = function() return {["session_logout"] = true} end
    kong.request.get_method = function() return "GET" end

    local conf = {
      logout_methods = {"GET", "POST"},
      logout_query_arg = "session_logout"
    }

    assert.truthy(session.logout(conf))
  end)

  it("logs out with POST request with body", function()
    ngx.req.get_post_args = function()
      return {["session_logout"] = true}
    end
    ngx.req.read_body = function() end
    kong.request.get_method = function() return "POST" end

    local conf = {
      logout_methods = {"POST"},
      logout_post_arg = "session_logout"
    }

    assert.truthy(session.logout(conf))
  end)

  it("logs out with DELETE request with body", function()
    ngx.req.get_post_args = function()
      return {["session_logout"] = true}
    end
    ngx.req.read_body = function() end
    kong.request.get_method = function() return "DELETE" end

    local conf = {
      logout_methods = {"DELETE"},
      logout_post_arg = "session_logout"
    }

    assert.truthy(session.logout(conf))
  end)

  it("logs out with DELETE request with query params", function()
    kong.request.get_query = function() return {["session_logout"] = true} end
    kong.request.get_method = function() return "DELETE" end

    local conf = {
      logout_methods = {"DELETE"},
      logout_query_arg = "session_logout"
    }

    assert.truthy(session.logout(conf))
  end)

  it("does not logout with GET requests when method is not allowed", function()
    kong.request.get_query = function() return {["session_logout"] = true} end
    kong.request.get_method = function() return "GET" end

    local conf = {
      logout_methods = {"DELETE"},
      logout_query_arg = "session_logout"
    }

    assert.falsy(session.logout(conf))
  end)

  it("does not logout with POST requests when method is not allowed", function()
    ngx.req.get_post_args = function()
      return {["session_logout"] = true}
    end
    kong.request.get_method = function() return "POST" end

    local conf = {
      logout_methods = {"DELETE"},
      logout_post_arg = "session_logout"
    }

    assert.falsy(session.logout(conf))
  end)
end)
