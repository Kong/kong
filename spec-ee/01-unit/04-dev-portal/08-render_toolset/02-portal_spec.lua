local getters = require "kong.portal.render_toolset.getters"
local handler    = require "kong.portal.render_toolset.handler"
local pl_stringx = require "pl.stringx"


local function table_length(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end


describe("portal", function()
  local portal
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("urls", function()
    before_each(function()
      stub(getters, "get_portal_urls").returns({
        api = "http://url_stuff.com/api",
        gui = "http://url_stuff.com/gui",
        current = "http://url_stuff.com/current",
      })

      portal = handler.new("portal")
    end)

    it("can fetch urls", function()
      local res = portal():urls()()

      assert.equals(table_length(res), 3)
    end)

    it("can get api url", function()
      local res = portal():urls():api()()

      assert.equals(res, "http://url_stuff.com/api")
    end)

    it("can get gui url", function()
      local res = portal():urls():gui()()

      assert.equals(res, "http://url_stuff.com/gui")
    end)

    it("can get current url", function()
      local res = portal():urls():current()()

      assert.equals(res, "http://url_stuff.com/current")
    end)
  end)

  describe("specs", function()
    before_each(function()
      stub(getters, "select_all_files").returns({{
          path = "content/a/b/c/dog.json",
          contents = "spec"
        },
        {
          path = "content/a/b/c/d/dog.json",
          contents = "spec"
        },
        {
          path = "content/x/y/z/dog.json",
          contents = "spec"
        },
        {
          path = "content/x/y/z/dog.md",
          contents = "content"
        },
        {
          path = "content/x/y/z/dog.txt",
          contents = "content"
        }}
      )
    end)

    describe("initializer", function()
      before_each(function()
        portal = handler.new("portal")
      end)

      it("can fetch specs", function()
        local res = portal():specs()()

        assert.equals(#res, 3)
        for i, v in ipairs(res) do
          assert.equals(v.contents, "spec")
        end
      end)
    end)

    describe("helpers", function()
      before_each(function()
        portal = handler.new("portal")
      end)

      it("can filter specs by included path", function()
        local res = portal():specs():filter_by_path('content/a')()

        assert.equals(#res, 2)
        for i, v in ipairs(res) do
          assert(pl_stringx.startswith(v.path, 'content/a'))
          assert.equals(v.contents, "spec")
        end
      end)

      it("can filter specs by included route", function()
        local res = portal():specs():filter_by_route('/x/y')()

        assert.equals(#res, 1)
        for i, v in ipairs(res) do
          assert(pl_stringx.startswith(v.path, 'content/x/y'))
          assert.equals(v.contents, "spec")
        end
      end)

      it("can return a specs route", function()
        local res = portal():specs():idx(1)()

        assert.equals(res.route, '/a/b/c/dog')
      end)
    end)
  end)

  describe("name", function()
    before_each(function()
      stub(getters, "get_portal_name").returns("WACKY PORTAL")
    end)

    describe("initializer", function()
      before_each(function()
        portal = handler.new("portal")
      end)

      it("can fetch specs", function()
        local res = portal():name()()

        assert.equals(res, "WACKY PORTAL")
      end)
    end)
  end)

  -- TODO: write config specs
  -- TODO: write redirect specs
end)
