-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
