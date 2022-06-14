-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local version = setmetatable({
  major = 2,
  minor = 8,
  patch = 0,
  --suffix = "rc.1"
}, {
  -- our Makefile during certain releases adjusts this line. Any changes to
  -- the format need to be reflected in both places
  __tostring = function(t)
    return string.format("%d.%d.%d%s", t.major, t.minor, t.patch,
                         t.suffix or "")
  end
})

return {
  _NAME = "kong",
  _VERSION = tostring(version),
  _VERSION_TABLE = version,
  _SERVER_TOKENS = "kong/" .. tostring(version),

  -- unified version string for CE and EE
  version = tostring(version),

  -- third-party dependencies' required version, as they would be specified
  -- to lua-version's `set()` in the form {from, to}
  _DEPENDENCIES = {
    nginx = { "1.21.4.1" },
  }
}
