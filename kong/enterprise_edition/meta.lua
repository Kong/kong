local package = {
  x = 0,
  y = 33,
  z = "-internal-preview",
}

local features = {
  _iteration = 1,
}

return {
  versions = {
    package  = setmetatable(package, {
      __tostring = function(t)
        return string.format("%d.%d%s", t.x, t.y, t.z or "")
      end,
    }),
    features = setmetatable(features, {
      __tostring = function(t)
        return string.format("v%d", t._iteration)
      end,
    }),
  },
}
