local log = require "kong.cmd.utils.log"
local singletons = require "kong.singletons"


local _M = {}


-- Temporary wrapper around :each implementing arbitrary filtering,
-- used throughout workspaces implementation
function _M.compat_find_all(dao_name, filt)
  local dao = singletons.db[dao_name]

  filt = filt or {}
  filt.__skip_rbac = nil -- remove skip_rbac from here

  local rows = {}
  local filtering = false

  if next(filt) then
    filtering = true
  end

  for row, err in dao:each() do
    if err then
      return nil, err
    end
    if filtering then
      local match = true
      for k,v in pairs(filt) do
        if row[k] ~= v then
          goto continue
        end
      end
      if match then
        rows[#rows + 1] = row
      end
    else
      rows[#rows + 1] = row
    end
    ::continue::
  end

  log.debug(debug.traceback("[legacy wrapper] using workspaces legacy wrapper"))
  return rows
end


return _M
