local rbac = require "kong.rbac"
local singletons = require "kong.singletons"

return {
  up = function(_, _, dao)
    singletons.dao = dao

    local users, err = dao.db:query("SELECT * FROM rbac_users")
    if err then
      return err
    end

    -- for each user, create a default role - or, if a role with the
    -- same name already exists, add the user to it
    for _, user in ipairs(users) do
      local _, err = rbac.create_default_role(user)
      if err then
        return err
      end
    end
  end
}
