local function mock(method)
  _G.kong = {
    request = {
      get_method = function() return method end,
      get_query_arg = function() return true end,
      get_body = function() return { session_logout = true } end,
    },
    log = {
      debug = function() end
    }
  }

  return require "kong.plugins.session.session"
end

describe("Plugin: Session - session.lua", function()
  local old_kong
  before_each(function()
    old_kong = _G.kong
  end)

  after_each(function()
    _G.kong = old_kong
    package.loaded["kong.plugins.session.session"] = nil
  end)

  it("logs out with GET request", function()
    local session = mock("GET")
    local conf = {
      logout_methods = { "GET", "POST" },
      logout_query_arg = "session_logout"
    }
    assert.truthy(session.logout(conf))
  end)

  it("logs out with POST request with body", function()
    local session = mock("POST")
    local conf = {
      logout_methods = { "POST" },
      logout_post_arg = "session_logout"
    }
    assert.truthy(session.logout(conf))
  end)

  it("logs out with DELETE request with body", function()
    local session = mock("DELETE")
    local conf = {
      logout_methods = { "DELETE" },
      logout_post_arg = "session_logout"
    }
    assert.truthy(session.logout(conf))
  end)

  it("logs out with DELETE request with query params", function()
    local session = mock("DELETE")
    local conf = {
      logout_methods = { "DELETE" },
      logout_query_arg = "session_logout"
    }
    assert.truthy(session.logout(conf))
  end)

  it("does not logout with GET requests when method is not allowed", function()
    local session = mock("GET")
    local conf = {
      logout_methods = { "DELETE" },
      logout_query_arg = "session_logout"
    }
    assert.falsy(session.logout(conf))
  end)

  it("does not logout with POST requests when method is not allowed", function()
    local session = mock("POST")
    local conf = {
      logout_methods = { "DELETE" },
      logout_post_arg = "session_logout"
    }
    assert.falsy(session.logout(conf))
  end)
end)
