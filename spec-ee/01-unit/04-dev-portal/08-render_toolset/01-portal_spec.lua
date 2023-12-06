-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local handler = require "kong.portal.render_toolset.handler"

describe("portal", function()
  local portal, snapshot, workspaces
  local kong_conf = {
    portal = "on",
    portal_gui_listeners = {"127.0.0.1:8003"},
    portal_api_listeners = {"127.0.0.1:8004"},
    portal_gui_host = "localhost.test",
    portal_gui_protocol = "http",
    portal_api_url = "http://api.localhost.test",
    portal_auth = "basic-auth",
  }

  lazy_setup(function()
    _G.kong = {}
    workspaces = require "kong.workspaces"

    kong.configuration = kong_conf

    ngx.ctx.render_ctx = {
      path = "default/hello-world",
      content = {
        layout = "hello-world.html",
      },
      portal = {
        name = "kong portal"
      },
      route_config = {},
    }

    kong.db = {}
    kong.db.files = {
      each = function()
        local files = {
          {
            path = "content/hello-world.txt",
            contents = "---layout: hello-world.html---",
          },
          {
            path = "content/a/b/c/dog.json",
            contents = "spec"
          },
        }
        local i = 0
        return function()
          i = i + 1
          return files[i]
        end
      end
    }

    kong.portal_router = { introspect = {} }

    workspaces.get_workspace = function()
      return {
        name = "default",
        config = {
          portal_developer_meta_fields = '[{"title":"full-name","label":"Full Name","validator":{"required":false,"type":"string"}}]',
        },
      }
    end
  end)

  before_each(function()
    snapshot = assert:snapshot()
    portal = handler().portal
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe(".workspace", function()
    it("returns current workspace name", function()
      assert.equals(portal.workspace, "default")
    end)
  end)

  describe(".name", function()
    it("returns current portal name", function()
      assert.equals(portal.name, "kong portal")
    end)
  end)

  describe(".auth", function()
    it("returns configuration value", function()
      assert.equals(portal.auth, "basic-auth")
    end)
  end)

  describe(".url", function()
    it("has current url", function()
      assert.equals(portal.url, "http://localhost.test/default")
    end)
  end)

  describe(".api_url", function()
    it("returns portal_api_url with workspace", function()
      assert.equals(portal.api_url, "http://api.localhost.test/default")
    end)

    it("returns empty string when portal_api_url empty", function()
      kong.configuration.portal_api_url = nil
      portal = handler().portal
      assert.equals(portal.api_url, '')
    end)
  end)

  describe(".spec", function()
    it("only contains specs", function()
      local res = portal.specs
      for i, v in ipairs(res) do
        assert.equals(v.body, "spec")
      end
    end)

    it("sets route on each spec", function()
      local res = portal.specs
      for i, v in ipairs(res) do
        assert.equals(v.route, "/a/b/c/dog")
      end
    end)
  end)

  describe(".files", function()
    it("contains all files", function()
      assert.equals(#portal.files, 2)
    end)
  end)

  describe(".developer_meta_fields", function()
    it("is a table", function()
      assert.is_table(portal.developer_meta_fields)
    end)

    it("returns formatted meta fields", function()
      local field = portal.developer_meta_fields[1]
      assert.equals(field.name, "full-name")
      assert.equals(field.label, "Full Name")
      assert.equals(field.required, false)
      assert.equals(field.type, "text")
    end)
  end)
end)
