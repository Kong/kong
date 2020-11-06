-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

describe("CLI commands", function()
  describe("'kong'", function()
    it("outputs usage by default", function()
      local _, stderr = helpers.kong_exec() -- 'kong'
      assert.matches("kong COMMAND [OPTIONS]", stderr, nil, true)
    end)

    it("don't remove the cool tagline", function()
      local ok, _, stdout = helpers.kong_exec("roar")
      assert.True(ok)
      assert.matches("Kong, Monolith destroyer.", stdout, nil, true)
    end)

    describe("errors", function()
      it("errors on invalid command", function()
        local _, stderr = helpers.kong_exec "foobar"
        assert.matches("No such command: foobar", stderr, nil, true)
      end)
    end)
  end)
end)
