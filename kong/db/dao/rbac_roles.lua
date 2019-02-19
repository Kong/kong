local rbac = require "kong.rbac"

-- XXX: EE is db needed? it should be possible to get it from self (or
-- singletons.db???)

return {
  get_users = function(self, db, role)
    return rbac.entity_relationships(db, role, "role", "user", "rbac_user_roles")
  end,

  get_entities = function(self, db, role)
    return rbac.entity_relationships(db, role, "role", "entity", "rbac_role_entities")
  end,
}
