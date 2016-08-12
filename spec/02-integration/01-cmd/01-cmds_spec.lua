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
