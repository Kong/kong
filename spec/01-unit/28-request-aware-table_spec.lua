local tablex = require "pl.tablex"

local rat

describe("Request aware table", function()
  local old_ngx
  local tab

  lazy_setup(function()
    old_ngx = ngx
    _G.ngx = {
      get_phase = function() return "access" end,
      var = {},
    }
    rat = require "kong.tools.request_aware_table"
  end)

  lazy_teardown(function()
    _G.ngx = old_ngx
  end)

  describe("with concurrency check enabled", function()
    local orig_t = {}

    before_each(function()
      tab = rat.new(orig_t, "on")
    end)

    it("allows defining a custom clear function", function()
      orig_t.persist = "persistent_value"
      orig_t.foo = "bar"
      orig_t.baz = "qux"

      -- custom clear function that keeps persistent_value
      tab.clear(function(t)
        for k in pairs(t) do
          if k ~= "persist" then
            t[k] = nil
          end
        end
      end)

      -- confirm persistent_value is the only key left
      assert.same(1, tablex.size(orig_t))
      assert.equal("persistent_value", tab.persist)

      -- clear the whole table and confirm it's empty
      tab.clear()
      assert.same(0, tablex.size(orig_t))
    end)
  end)
end)
