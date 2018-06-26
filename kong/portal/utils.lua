local enums       = require "kong.enterprise_edition.dao.enums"

local _M = {}


-- Validates an email address
_M.validate_email = function(str)
  if str == nil then
    return nil
  end

  if type(str) ~= 'string' then
    error("Expected string")
    return nil
  end

  local lastAt = str:find("[^%@]+$")
  local localPart = str:sub(1, (lastAt - 2)) -- Returns the substring before '@' symbol
  local domainPart = str:sub(lastAt, #str) -- Returns the substring after '@' symbol
  -- we werent able to split the email properly
  if localPart == nil then
    return nil
  end

  if domainPart == nil then
    return nil
  end

  -- local part is maxed at 64 characters
  if #localPart > 64 then
    return nil
  end

  -- domains are maxed at 253 characters
  if #domainPart > 253 then
    return nil
  end

  if lastAt >= 65 then
    return nil
  end

  local quotes = localPart:find("[\"]")
  if type(quotes) == 'number' and quotes > 1 then
    return nil
  end

  if localPart:find("%@+") and quotes == nil then
    return nil
  end

  if not domainPart:find("%.") then
    return nil
  end

  if domainPart:find("%.%.") then
    return nil
  end
  if localPart:find("%.%.") then
    return nil
  end

  if not str:match('[%w]*[%p]*%@+[%w]*[%.]?[%w]*') then
    return nil
  end

  return true
end

_M.get_developer_status = function(consumer)
  local status = consumer.status
  return {
    status = status,
    label  = enums.CONSUMERS.STATUS_LABELS[status]
  }
end


return _M
