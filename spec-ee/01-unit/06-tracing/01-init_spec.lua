-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
