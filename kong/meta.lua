-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ee_meta = require "kong.enterprise_edition.meta"

local version = setmetatable({
  major = 2,
  minor = 2,
  patch = 1,
  -- suffix = ""
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
  _VERSION = tostring(ee_meta.versions.package) .. "-enterprise-edition",
  _VERSION_TABLE = ee_meta.versions.package,
  _SERVER_TOKENS = "kong/" .. tostring(ee_meta.versions.package) .. "-enterprise-edition",

  _CORE_VERSION = tostring(version),
  _CORE_VERSION_TABLE = version,

  -- third-party dependencies' required version, as they would be specified
  -- to lua-version's `set()` in the form {from, to}
  _DEPENDENCIES = {
    nginx = { "1.17.8.2" },
  }
}
