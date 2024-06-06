local helpers = require "spec.helpers"
local meta = require "kong.meta"

describe("kong cli verbose output", function()
  it("--vv outputs debug level log", function()
    local _, stderr, stdout = assert(helpers.kong_exec("version --vv"))
    -- globalpatches debug log will be printed by upper level resty command that runs kong.cmd
    assert.matches("installing the globalpatches", stderr)
    assert.matches("Kong: " .. meta._VERSION, stdout, nil, true)
  end)
end)
