describe(".init", function()
  local tracing = require "kong.tracing"

  describe("with a sane configuration", function()
    it("initializes the module", function()
      assert(tracing.init({
        tracing = true,
        tracing_types = {"all"},
      }))
    end)
  end)

  describe("with an invalid configuration", function()
    it("fails with no config table", function()
      assert.has_error(function()
        tracing.init()
      end)
    end)

    it("fails with invalid tracing type", function()
      assert.has_error(function()
        tracing.init({tracing = "foo"})
      end)
    end)

    it("fails with invalid tracing.tracing_types type", function()
      assert.has_error(function()
        tracing.init({
          tracing = true,
          tracing_types = "all",
        })
      end)
    end)
  end)
end)
