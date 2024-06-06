local _M = {}


-- return first listener matching filters
function _M.select_listener(listeners, filters)
  for _, listener in ipairs(listeners) do
    local match = true

    for filter, value in pairs(filters) do
      if listener[filter] ~= value then
        match = false
        break
      end
    end

    if match then
      return listener
    end
  end
end


function _M.prepare_variable(variable)
  if variable == nil then
    return ""
  end

  return tostring(variable)
end


return _M
