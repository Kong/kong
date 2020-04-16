local strip = (require "pl.stringx").strip

local version = setmetatable({
  x = 1,
  y = 5,
  z = 0,
  e = 1,
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
