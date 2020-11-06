-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local strip = (require "pl.stringx").strip

local version = setmetatable({
  x = 2,
  y = 2,
  z = 0,
  e = 0,
}, {
  __tostring = function(t)
    return string.format("%d.%d.%d.%d", t.x, t.y, t.z, t.e)
  end
})

local package = setmetatable({
  -- Note: line below is changed at build time in kong-distributions
  -- build-kong.sh script to add certain suffixes; e.g., internal previews
  -- automation add a suffix "internal-preview" at build time
  suffix = "dev",
}, {
  __tostring = function(t)
    local suffix = strip(t.suffix)
    return string.format("%s%s", version, suffix ~= "" and "-" .. suffix or "")
  end
})

local features = {
  _iteration = 1,
}

return {
  versions = {
    package  = package,
    features = setmetatable(features, {
      __tostring = function(t)
        return string.format("v%d", t._iteration)
      end,
    }),
  },
}
