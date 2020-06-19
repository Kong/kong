local rbac = require "kong.rbac"

return {
  up = function(_, _, dao)
    -- Setup and Admin user by default if ENV var is set
    local password = os.getenv("KONG_PASSWORD")

    if not password then
      return
    end

    local role, err = dao.rbac_roles:find_all({name = "super-admin"})
    if err then
      return err
    end
    role = role[1]

    -- an old migration in 0.32 (the migration is deleted)
    -- could have already created a kong_admin user, do not overwrite
    -- alternatively, this may have been run in 0.33/0.34; this
    -- migration was moved in order to support a DDL change in the
    -- rbac_users table
    local user, err = dao.rbac_users:find_all({ name = "kong_admin" })
    if err then
      return err
    end

    if user[1] then
      return
    end

    local user, err = dao.rbac_users:insert({
      name = "kong_admin",
      user_token = password,
      enabled = true,
      comment = "Initial RBAC Secure User"
    })
    if err then
      return err
    end

    -- associated this user with the super-admin role
    local _, err = dao.rbac_user_roles:insert({
      user_id = user.id,
      role_id = role.id
    })
    if err then
      return err
    end

    local _, err = rbac.create_default_role(user)
    if err then
      return err
    end
  end
}
