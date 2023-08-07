-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ee_meta = (require "kong.enterprise_edition.meta")
local ee_version_table = ee_meta._VERSION_TABLE

return {
  _NAME = "kong",
  _VERSION = ee_meta._VERSION,
  _VERSION_TABLE = ee_meta._VERSION_TABLE,
  _SERVER_TOKENS = ee_meta._SERVER_TOKENS,

  -- CE version string (needed for compatability)
  version = ee_meta.version,
  core_version = string.format("%d.%d.%d%s",
    ee_version_table.major,
    ee_version_table.minor,
    ee_version_table.patch,
    ee_version_table.suffix or ""
  ),

  -- third-party dependencies' required version, as they would be specified
  -- to lua-version's `set()` in the form {from, to}
  _DEPENDENCIES = {
    nginx = { "1.21.4.2" },
  }
}
