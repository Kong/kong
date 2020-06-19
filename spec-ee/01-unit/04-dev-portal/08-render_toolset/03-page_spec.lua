local handler    = require "kong.portal.render_toolset.handler"

describe("page", function()
  local page, snapshot, singletons, workspaces

  lazy_setup(function()
    singletons = require "kong.singletons"
    workspaces = require "kong.workspaces"

    singletons.render_ctx = {
      path = "/default/hello-world",
      route_config = {
        headmatter = {
          title = "Hello World",
          sidebar = {
            show = true,
            contents = {
              "a", "b", "c",
            }
          }
        }
      }
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
    page = handler().page
  end)

  after_each(function()
    snapshot:revert()
  end)

  it('exposes content values', function()
    assert.equals(page.title, "Hello World")
  end)

  it('exposes nested content values', function()
    assert.equals(page.sidebar.show, true)
  end)

  describe('.path', function()
    it('returns the currently active path', function()
      assert.equals(page.route, 'hello-world')
    end)
  end)

  describe('.url', function()
    it('returns the url with currently active path', function()
      assert.equals(page.url, 'http://localhost.com/default/hello-world')
    end)
  end)

  describe('.breadcrumbs', function()
    it('is a list', function()
      assert.is_table(page.breadcrumbs)
    end)

    it('returns list of page crumbs', function()
      for _, crumb in ipairs(page.breadcrumbs) do
        assert.equals(crumb.name, "hello-world")
        assert.equals(crumb.display_name, "Hello World")
        assert.equals(crumb.path, "hello-world")
        assert.truthy(crumb.is_last)
        assert.truthy(crumb.is_first)
      end
    end)
  end)

  describe('.body', function()
    before_each(function()
      snapshot = assert:snapshot()
    end)
  
    it("can parse body from .txt file", function()
      singletons.render_ctx = {
        path = "/default/hello-world",
        content = {},
        route_config = {
          body = "## this is body text",
          path_meta = {
            extension = "txt",
          },
        },
      }

      page = handler().page
      assert.equals(page.body, "## this is body text")
    end)

    it("can parse markdown from body from .md file", function()
      singletons.render_ctx = {
        path = "/default/hello-world",
        content = {},
        route_config = {
          path_meta = {
            extension = "md",
          },
          body = "## this is body text",
        }
      }

      page = handler().page
      local arg = string.gsub(page.body, "%s+", "")
      local exp = string.gsub("<h2>this is body text</h2>", "%s+", "")
      assert.equals(arg, exp)
    end)

    it("does not parse markdown from body from .txt file", function()
      singletons.render_ctx = {
        path = "/default/hello-world",
        content = {},
        route_config = {
          path_meta = {
            extension = "txt",
          },
          body = "## this is body text",
        }
      }

      page = handler().page
      local arg = string.gsub(page.body, "%s+", "")
      local exp = string.gsub("## this is body text", "%s+", "")
      assert.equals(arg, exp)
    end)
  end)
end)
