-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local handler    = require "kong.portal.render_toolset.handler"

describe("user", function()
  local user, snapshot, workspaces

  lazy_setup(function()
    _G.kong = {}
    workspaces = require "kong.workspaces"

    ngx.ctx.render_ctx = {
      path = "/default/hello-world",
    }

    kong.configuration = {
      portal = "on",
      portal_gui_listeners = {"127.0.0.1:8003"},
      portal_api_listeners = {"127.0.0.1:8004"},
      portal_gui_host = "localhost.test",
      portal_gui_protocol = "http",
      portal_api_url = "http://api.localhost.test",
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
      assert.equals(user.is_authenticated, false)
    end)

    it("returns true when logged in", function()
      ngx.ctx.render_ctx.developer = {
        username = "nijiko"
      }

      assert.equals(user.is_authenticated, true)
    end)
  end)


  describe(".has_role()", function()
    lazy_setup(function()
      local rbac = require "kong.rbac"
      stub(rbac, "get_user_roles").returns({{
        created_at = 1568242275,
        id = "76926f74-df96-4cf9-8c5a-d7ea7c569acf",
        is_default = false,
        name = "__PORTAL-red"
      }, {
        created_at = 1568242275,
        id = "76926f74-df96-4cf9-8c5a-d7ea7c569acf",
        is_default = false,
        name = "__PORTAL-blue"
      }, {
        comment = "Default user role generated for __PORTAL-b79ad05a-8484-4af4-a814-f7ef4b280859",
        created_at = 1568242275,
        id = "d2c7335e-9287-4e09-8d9d-cfc33aab267a",
        is_default = true,
        name = "__PORTAL-b79ad05a-8484-4af4-a814-f7ef4b280859"
      }})

      ngx.ctx.render_ctx.developer = {
        username = "nijiko",
        rbac_user = "duder",
      }
    end)

    it("returns false when developer does not have role", function()
      assert.falsy(user.has_role("green"))
    end)

    it("returns true when developer does have role", function()
      assert.truthy(user.has_role("blue"))
      assert.truthy(user.has_role("red"))
    end)
  end)


  describe(".get", function()
    it("returns developer field", function()
      ngx.ctx.render_ctx.developer = {
        username = "nijiko"
      }

      assert.equals(user.get("username"), "nijiko")
    end)
  end)
end)
