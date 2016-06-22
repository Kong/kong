local helpers = require "spec.helpers"

describe("CLI commands", function()
  describe("'kong'", function()
    it("outputs usage by default", function()
      local _, stderr, stdout = helpers.kong_exec() -- 'kong'
      assert.is_nil(stdout)
      assert.matches("kong COMMAND [OPTIONS]", stderr, nil, true)
    end)

    describe("errors", function()
      it("errors on invalid command", function()
        local _, stderr, stdout = helpers.kong_exec "foobar"
        assert.is_nil(stdout)
        assert.matches("No such command: foobar", stderr, nil, true)
      end)
    end)
  end)
end)
