local helpers = require "spec.helpers"

describe("kong runner", function()

  it("fails when the given file argument does not exist", function()
    local _, stderr = helpers.kong_exec "runner notexists.lua"
    assert.not_equal("", stderr)
  end)

  it("runs code from stdin if no arg is given", function()
    local _, _, stdout = helpers.execute(
      [[ echo 'print(#args)' | ]] .. helpers.bin_path .. " runner " )
    assert.equals("0", string.sub(stdout, 1, -2) )
  end)

  it("runs code from a given file argument", function()
      local tmpfile = require("pl.path").tmpname()  -- this creates the file!
      finally(function() os.remove(tmpfile) end)

      os.execute([[echo 'print(#args)' >]] .. tmpfile)
      local _, _, stdout = helpers.execute(
        helpers.bin_path .. [[ runner ]] .. tmpfile .. " foo")

      assert.equals("2", string.sub(stdout, 1, -2))
  end)

  it("errs with sintactically wrong lua file", function()
    local tmpfile = require("pl.path").tmpname()  -- this creates the file!
    finally(function() os.remove(tmpfile) end)
    os.execute([[echo "print('roar'" >]] .. tmpfile)
    local ok = helpers.execute(helpers.bin_path .. [[ runner ]] .. tmpfile)
    assert.is_false(ok)
  end)

  it("has access to kong variable", function()
    local _, _, stdout = helpers.execute([[
      echo 'print(tostring(kong))' | ]] ..
      helpers.bin_path .. " runner " )
    assert.matches("table", string.sub(stdout, 1, -2) )
  end)

end)
