local vitals = require("kong.vitals")

local _M = {}


local function additional_tables(dao)
  return vitals.table_names(dao)
end

_M.additional_tables = additional_tables

return _M
