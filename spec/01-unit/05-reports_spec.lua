local reports = require "kong.core.reports"

describe("reports", function()
  describe("get_system_infos()", function()
    it("gets infos about current host", function()
      local infos = reports.get_system_infos()
      assert.is_number(infos.cores)
      assert.is_string(infos.hostname)
      assert.is_string(infos.uname)
      assert.not_matches("\n$", infos.hostname)
      assert.not_matches("\n$", infos.uname)
    end)
  end)
end)
