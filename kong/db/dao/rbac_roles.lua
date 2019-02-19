local rbac = require "kong.rbac"

return {
  get_users = function(self, db, role)
    return rbac.entity_relationships(db, role, "role", "user", "rbac_user_roles")
  end
}
