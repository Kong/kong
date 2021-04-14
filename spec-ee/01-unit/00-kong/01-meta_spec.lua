-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
