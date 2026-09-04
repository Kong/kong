local is_valid_version = require("kong.clustering.services.sync.strategies.postgres").is_valid_version
local VER_PREFIX = "v02_"
local str_rep = string.rep

describe("is_valid_version", function()
    it("accept valid version", function()
        -- all zero version
        local ver = VER_PREFIX .. str_rep("0", 28)
        assert.True(is_valid_version(nil, ver))

        -- non-hexidecimal
        ver = VER_PREFIX .. str_rep("9", 28)
        assert.True(is_valid_version(nil, ver))

        -- hexidecimal
        ver = VER_PREFIX .. str_rep("f", 28)
        assert.True(is_valid_version(nil, ver))
    end)

    it("reject invalid version", function()
        -- invalid prefix
        local ver = "v01_" .. str_rep("0", 28)
        assert.False(is_valid_version(nil, ver))

        -- invalid length
        ver = VER_PREFIX .. str_rep("0", 27)
        assert.False(is_valid_version(nil, ver))

        -- invalid non-hexidecimal
        ver = VER_PREFIX .. str_rep("-", 28)
        assert.False(is_valid_version(nil, ver))

        -- invalid hexidecimal
        ver = VER_PREFIX .. str_rep("g", 28)
        assert.False(is_valid_version(nil, ver))
    end)
end)

