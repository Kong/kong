-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local shell = require "resty.shell"

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

      shell.run([[echo 'print(#args)' >]] .. tmpfile, nil, 0)
      local _, _, stdout = helpers.execute(
        helpers.bin_path .. [[ runner ]] .. tmpfile .. " foo")

      assert.equals("2", string.sub(stdout, 1, -2))
  end)

  it("errs with sintactically wrong lua file", function()
    local tmpfile = require("pl.path").tmpname()  -- this creates the file!
    finally(function() os.remove(tmpfile) end)
    shell.run([[echo "print('roar'" >]] .. tmpfile, nil, 0)
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
