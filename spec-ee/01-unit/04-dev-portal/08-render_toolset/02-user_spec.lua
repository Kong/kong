local handler    = require "kong.portal.render_toolset.handler"

describe("user", function()
  local user, snapshot, singletons, workspaces

  lazy_setup(function()
    singletons = require "kong.singletons"
    workspaces = require "kong.workspaces"

    singletons.render_ctx = {
      route = "default/hello-world"
    }

    singletons.db = {
      files = {
        select_all = function() return {} end
      }
    }

    singletons.configuration = {
      portal = "on",
      portal_gui_listeners = {"127.0.0.1:8003"},
      portal_api_listeners = {"127.0.0.1:8004"},
      portal_gui_host = "localhost.com",
      portal_gui_protocol = "http",
      portal_api_url = "http://api.localhost.com",
      portal_auth = "basic-auth",
    }

    workspaces.get_workspace = function()
      return {
        name = "default",
        config = {},
      }
    end
  end)

  before_each(function()
    snapshot = assert:snapshot()
    user = handler().user
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe(".is_authenticated()", function()
    it("returns false when logged out", function()
      assert.equals(user.is_authenticated(), false)
    end)

    it("returns true when logged in", function()
      singletons.render_ctx.developer = {
        username = "nijiko"
      }

      assert.equals(user.is_authenticated(), true)
    end)
  end)


  describe(".get", function()
    it("returns developer field", function()
      singletons.render_ctx.developer = {
        username = "nijiko"
      }

      assert.equals(user.get("username"), "nijiko")
    end)
  end)
end)
