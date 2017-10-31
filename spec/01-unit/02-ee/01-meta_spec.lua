describe("ee meta", function()
  local ee_meta = require "kong.enterprise_edition.meta"

  describe("versions", function()
    local versions = ee_meta.versions

    it("has a versions table", function()
      assert.is_table(versions)
    end)

    it("has a package version", function()
      assert.is_table(versions.package)
      assert.matches("^%d%.%d+", tostring(versions.package))
    end)

    it("has a core features version", function()
      assert.is_table(versions.features)
      assert.matches("^v%d+$", tostring(versions.features))
    end)
  end)
end)
