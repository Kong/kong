-- This file is ment to be overwritten during the kong-distributions
-- process. Returning an empty 2 level dictionary to comply with the
-- interface.

local constants = {
  featureset = {
    full = {
      conf = {},
      abilities = {}
    },
    free = {
      conf = {},
      abilities = {}
    },
  }
}
return setmetatable(constants, {__index = function() return {} end })
