local handler = require "kong.portal.render_toolset.handler"

describe("page", function()
  local theme, snapshot, singletons, workspaces

  lazy_setup(function()
    singletons = require "kong.singletons"
    workspaces = require "kong.workspaces"

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

    singletons.render_ctx = {
      path = "/default/hello-world",
      content = {
        title = "Hello World",
        sidebar = {
          show = true,
          contents = {
            "a", "b", "c",
          }
        },
      },
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
    theme = handler().theme
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("empty color/font declerations", function()
    lazy_setup(function()
      singletons.render_ctx.theme = {}
    end)

    it('returns nil with no theme set', function()
      assert.is_nil(theme.colors.green)
      assert.is_nil(theme.colors.blue)
      assert.is_nil(theme.colors.red)

      assert.is_nil(theme.fonts.fancy)
      assert.is_nil(theme.fonts.ugly)
      assert.is_nil(theme.fonts.bold)
    end)

    it('returns nil from helper with no theme set', function()
      assert.is_nil(theme.color("green"))
      assert.is_nil(theme.color("blue"))
      assert.is_nil(theme.color("red"))

      assert.is_nil(theme.font("fancy"))
      assert.is_nil(theme.font("ugly"))
      assert.is_nil(theme.font("bold"))
    end)
  end)

  describe("non-empty color/font declerations", function()
    lazy_setup(function()
      singletons.render_ctx.theme = {
        colors = {
          green = "#abcdef",
          blue  = {
            value = "#123456",
          },
          red   = {
            dog = { "cat" }
          }
        },
        fonts = {
          fancy = "sofancy",
          ugly  = {
            value = "muchugly",
          },
          bold   = {
            dog = { "cat" }
          }
        }
      }
    end)

    it('normalizes color values', function()
      assert.equals(theme.colors.green, "#abcdef")
      assert.equals(theme.colors.blue, "#123456")
      assert.is_nil(theme.colors.red)

      assert.equals(theme.color("green"), "#abcdef")
      assert.equals(theme.color("blue"), "#123456")
      assert.is_nil(theme.color("red"))
    end)
  
    it('normalizes font values', function()
      assert.equals(theme.fonts.fancy, "sofancy")
      assert.equals(theme.fonts.ugly, "muchugly")
      assert.is_nil(theme.fonts.bold)

      assert.equals(theme.font("fancy"), "sofancy")
      assert.equals(theme.font("ugly"), "muchugly")
      assert.is_nil(theme.font("bold"))
    end)
  end)
end)
