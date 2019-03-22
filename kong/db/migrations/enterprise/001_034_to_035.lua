return {
  postgres = {
    up = [[
     DO $$
     BEGIN
     ALTER TABLE IF EXISTS ONLY "rbac_user_roles"
       ADD CONSTRAINT rbac_user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES rbac_roles(id) ON DELETE CASCADE;

     ALTER TABLE IF EXISTS ONLY "rbac_user_roles"
       ADD CONSTRAINT rbac_user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES rbac_users(id) ON DELETE CASCADE;

     ALTER TABLE IF EXISTS ONLY "rbac_role_entities"
       ADD CONSTRAINT rbac_role_entities_role_id_fkey FOREIGN KEY (role_id) REFERENCES rbac_roles(id) ON DELETE CASCADE;

     CREATE INDEX IF NOT EXISTS rbac_role_entities_role_idx on rbac_role_entities(role_id);

     ALTER TABLE IF EXISTS ONLY "rbac_role_endpoints"
       ADD CONSTRAINT rbac_role_endpoints_role_id_fkey FOREIGN KEY (role_id) REFERENCES rbac_roles(id) ON DELETE CASCADE;

     CREATE INDEX IF NOT EXISTS rbac_role_endpoints_role_idx on rbac_role_endpoints(role_id);
     END
     $$;
    ]],
  },
  cassandra = {
    up = [[
      CREATE INDEX IF NOT EXISTS ON rbac_user_roles(role_id);
    ]],
  }


}
