local uuid = require "resty.jit-uuid"


local re_find       = ngx.re.find


local uuid_regex = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"


local _M = {}


--- Generates a v4 uuid.
-- @function uuid
-- @return string with uuid
_M.uuid = uuid.generate_v4


function _M.is_valid_uuid(str)
  if type(str) ~= 'string' or #str ~= 36 then
    return false
  end
  return re_find(str, uuid_regex, 'ioj') ~= nil
end


-- function below is more acurate, but invalidates previously accepted uuids and hence causes
-- trouble with existing data during migrations.
-- see: https://github.com/thibaultcha/lua-resty-jit-uuid/issues/8
-- function _M.is_valid_uuid(str)
--  return str == "00000000-0000-0000-0000-000000000000" or uuid.is_valid(str)
--end


return _M
