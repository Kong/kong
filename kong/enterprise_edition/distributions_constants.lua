-- This file is ment to be overwritten during the kong-distributions
-- process. Returning an empty 2 level dictionary to comply with the
-- interface.

return setmetatable({}, {__index = function() return {} end })
