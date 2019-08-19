local getters = require "kong.portal.render_toolset.getters"
local handler    = require "kong.portal.render_toolset.handler"

describe("page", function()
  local page
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
  end)

  after_each(function()
    snapshot:revert()
  end)

  stub(getters, "get_page_content").returns({
    title = "WACKY PORTAL",
    sidebar = {
      show = true,
      contents = {
        "a", "b", "c",
      }
    }
  })

  before_each(function()
    page = handler.new("page")
  end)

  it('can access non-nested values', function()
    local res = page('title')()

    assert.equals(res, "WACKY PORTAL")
  end)

  it('can access nested values', function()
    local res = page('sidebar.show')()

    assert.equals(res, true)
  end)

  it('can chain on returned values', function()
    local res = page('title'):lower()()

    assert.equals(res, "wacky portal")
  end)
end)
