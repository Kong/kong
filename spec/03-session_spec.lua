local helpers = require "spec.helpers"
local session = require "kong.plugins.session.session"

describe("Plugin: Session - session.lua", function()
  local old_ngx

  before_each(function()
    old_ngx = {
      var = {},
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
    ngx.req.get_uri_args = function()
      return {["session_logout"] = true}
    end
    ngx.var.request_method = "GET"

    conf = {
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
    ngx.var.request_method = "POST"

    conf = {
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
    ngx.var.request_method = "DELETE"
    
    conf = {
      logout_methods = {"DELETE"},
      logout_post_arg = "session_logout"
    }

    assert.truthy(session.logout(conf))
  end)

  it("logs out with DELETE request with query params", function()
    ngx.req.get_uri_args = function()
      return {["session_logout"] = true}
    end
    ngx.var.request_method = "DELETE"

    conf = {
      logout_methods = {"DELETE"},
      logout_query_arg = "session_logout"
    }

    assert.truthy(session.logout(conf))
  end)

  it("does not logout with GET requests when method is not allowed", function()
    ngx.req.get_uri_args = function()
      return {["session_logout"] = true}
    end
    ngx.var.request_method = "GET"

    conf = {
      logout_methods = {"DELETE"},
      logout_query_arg = "session_logout"
    }

    assert.falsy(session.logout(conf))
  end)

  it("does not logout with POST requests when method is not allowed", function()
    ngx.req.get_post_args = function()
      return {["session_logout"] = true}
    end
    ngx.var.request_method = "POST"

    conf = {
      logout_methods = {"DELETE"},
      logout_post_arg = "session_logout"
    }

    assert.falsy(session.logout(conf))
  end)
end)
