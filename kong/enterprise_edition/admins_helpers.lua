local enums = require "kong.enterprise_edition.dao.enums"
local _M = {}

local function validate(params, dao, http_method)
  -- how many rows do we expect to find?
  local max_count = http_method == "POST" and 0 or 1

  -- get all rbac users
  local rbac_users, err = dao.rbac_users:run_with_ws_scope({},
      dao.rbac_users.find_all)

  if err then
    -- unable to complete validation, so no success and no validation messages
    return nil, nil, err
  end

  local matches = 0
  for _, user in ipairs(rbac_users) do
    if user.name == params.username or
       user.name == params.custom_id or
       user.name == params.email then

      matches = matches + 1
    end
  end

  if matches > max_count then
    return false, "rbac_user already exists"
  end

  -- now check admin consumers
  local admins, err = dao.consumers:run_with_ws_scope({},
      dao.consumers.find_all, { type =  enums.CONSUMERS.TYPE.ADMIN })

  if err then
    -- unable to complete validation, so no success and no validation messages
    return nil, nil, err
  end

  matches = 0
  for _, admin in ipairs(admins) do
    if (admin.custom_id and admin.custom_id == params.custom_id) or
      (admin.username and admin.username == params.username) or
      (admin.email and admin.email == params.email) then

      matches = matches + 1
    end
  end

  if matches > max_count then
    return false, "consumer already exists"
  end

  return true
end
_M.validate = validate

return _M
