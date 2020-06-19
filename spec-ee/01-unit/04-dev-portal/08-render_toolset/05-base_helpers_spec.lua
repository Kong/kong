local helpers = require "kong.portal.render_toolset.helpers"

describe("base helpers", function()
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("markdown", function()
    it("can parse markdown into html", function()
      local elements = {
        ["# h1"] = "<h1>h1</h1>",
        ["## h2"] = "<h2>h2</h2>",
        ["### h3"] = "<h3>h3</h3>",
        ["#### h4"] = "<h4>h4</h4>",
        ["##### h5"] = "<h5>h5</h5>",
        ["p"] = "<p>p</p>",
        ["![doggo](doggo.jpg)"] = '<p><imgsrc="doggo.jpg"alt="doggo"/></p>'
      }

      for k, v in pairs(elements) do
        local el = string.gsub(helpers.markdown(k), "%s+", "")
        assert.equals(el, v)
      end
    end)
  end)
end)
