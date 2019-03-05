local rbac = require "kong.rbac"

return {
  get_roles = function(self, db, user)
    return rbac.entity_relationships(db, user, "user", "role", "rbac_user_roles")
  end
}
