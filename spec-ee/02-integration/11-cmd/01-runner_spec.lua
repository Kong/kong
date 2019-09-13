local helpers = require "spec.helpers"

describe("kong runner", function()

  it("fails when the given file argument does not exist", function()
    local _, stderr = helpers.kong_exec "runner notexists.lua"
    assert.not_equal("", stderr)
  end)

  it("runs code from stdin if no arg is given", function()
    local _, _, stdout = helpers.execute(
      [[ echo 'print("roar")' | ]] .. helpers.bin_path .. " runner " )
    assert.equals("roar", string.sub(stdout, 1, -2) )
  end)

  it("runs code from a given file argument", function()
      local tmpfile = require("pl.path").tmpname()  -- this creates the file!
      finally(function() os.remove(tmpfile) end)

      os.execute([[echo "print('roar')" >]] .. tmpfile)
      local _, _, stdout = helpers.execute(
        helpers.bin_path .. [[ runner ]] .. tmpfile)

      assert.equals("roar", string.sub(stdout, 1, -2))
  end)

  it("errs with sintactically wrong lua file", function()
    local tmpfile = require("pl.path").tmpname()  -- this creates the file!
    finally(function() os.remove(tmpfile) end)
    os.execute([[echo "print('roar'" >]] .. tmpfile)
    local ok = helpers.execute(helpers.bin_path .. [[ runner ]] .. tmpfile)
    assert.is_false(ok)
  end)


end)
