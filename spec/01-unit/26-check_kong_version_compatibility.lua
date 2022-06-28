_G.kong = {
    version = "3.0",
    configuration = {},
}

local check_kong_version_compatibility = require("kong.clustering.utils").check_kong_version_compatibility

describe("check_kong_version_compatibility", function()
    it("major comparing", function()
        assert.same({
            nil, "data plane version 2.0.1 is incompatible with control plane version 3.0.1 (3.x.y are accepted)", "kong_version_incompatible",
        }, { check_kong_version_compatibility("3.0.1", "2.0.1", "suffix") })

        assert.same({
            nil, "data plane version 2.0.1 is incompatible with control plane version 1.0.1 (1.x.y are accepted)", "kong_version_incompatible",
        }, { check_kong_version_compatibility("1.0.1", "2.0.1", "suffix") })

        assert.same({
            true, nil, "normal",
        }, { check_kong_version_compatibility("2.0.2", "2.0.1", "suffix") })

        assert.same({
            true, nil, "normal",
        }, { check_kong_version_compatibility("3.0.1", "3.0.2", "suffix") })
    end)

    it("minor comparing", function()
        assert.same({
            nil, "data plane version 2.1.1 is incompatible with control plane version 3.1.1 (3.x.y are accepted)", "kong_version_incompatible",
        }, { check_kong_version_compatibility("3.1.1", "2.1.1", "suffix") })

        assert.same({
            nil, "data plane version 2.1.1 is incompatible with older control plane version 2.0.1", "kong_version_incompatible",
        }, { check_kong_version_compatibility("2.0.1", "2.1.1", "suffix") })

        assert.same({
            true, nil, "normal",
        }, { check_kong_version_compatibility("2.1.2", "2.0.1", "suffix") })

        assert.same({
            true, nil, "normal",
        }, { check_kong_version_compatibility("3.3.1", "3.0.2", "suffix") })
    end)

    it("sepcial cases", function()
        assert.same({
            true, nil, "normal",
        }, { check_kong_version_compatibility("3.0.1", "2.8.5", "suffix") })

        assert.same({
            true, nil, "normal",
        }, { check_kong_version_compatibility("3.0.1", "2.8.2", "suffix") })
        

        assert.same({
            nil, "data plane version 3.0.2 is incompatible with control plane version 2.8.1 (2.x.y are accepted)", "kong_version_incompatible",
        }, { check_kong_version_compatibility("2.8.1", "3.0.2", "suffix") })
    end)
end)
