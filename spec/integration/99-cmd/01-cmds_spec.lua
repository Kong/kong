local helpers = require "spec.helpers"

local function exec(...)
  local args = {...}
  table.insert(args, 1, helpers.bin_path)
  local cmd = table.concat(args, " ")
  return helpers.execute(cmd)
end

describe("CLI commands", function()
  describe("'kong'", function()
    it("outputs usage by default", function()
      local ok, _, stdout, stderr = exec() -- 'kong'
      assert.False(ok)
      assert.equal("", stdout)
      assert.matches("kong COMMAND [OPTIONS]", stderr, nil, true)
    end)

    describe("errors", function()
      it("errors on invalid command", function()
        local ok, _, stdout, stderr = exec("foobar")
        assert.False(ok)
        assert.equal("", stdout)
        assert.matches("No such command: foobar", stderr, nil, true)
      end)
    end)
  end)
end)
