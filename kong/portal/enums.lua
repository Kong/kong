local _M = {}


_M.CONSUMERS = {
  STATUS = {
    ["APPROVED"] = 0,
    ["PENDING"] = 1,
    ["REJECTED"] = 2,
    ["REVOKED"] = 3,
    ["INVITED"] = 4
  },
  TYPE = {
    ["PROXY"] = 0,
    ["DEVELOPER"] = 1
  }
}


function _M.get_key_from_value(enums, value)
  for k, v in pairs(enums) do
    if v == value then
      return k
    end
  end

  return nil
end


return _M
