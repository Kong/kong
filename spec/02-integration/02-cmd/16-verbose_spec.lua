local helpers = require "spec.helpers"
local meta = require "kong.meta"

describe("kong cli verbose output", function()
  it("--vv outputs debug level log", function()
    local _, stderr, stdout = assert(helpers.kong_exec("version --vv"))
    assert.matches("gracefully shutting down", stderr)
    assert.matches("Kong: " .. meta._VERSION, stdout, nil, true)
  end)
end)
