-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local version = setmetatable({
    major = 3,
    minor = 6,
    patch = 0,
    ee_patch = 0,
    --suffix = "rc.1"
}, {
    __tostring = function(t)
        return string.format("%d.%d.%d.%d%s", t.major, t.minor, t.patch, t.ee_patch,
            t.suffix or "")
    end
})

return {
    _VERSION = tostring(version) .. "-enterprise-edition",
    _VERSION_TABLE = version,
    _SERVER_TOKENS = "kong/" .. tostring(version) .. "-enterprise-edition",

    version = tostring(version),
  }
