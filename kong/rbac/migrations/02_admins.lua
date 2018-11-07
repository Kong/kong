-- In 0.33, this migration created a consumer, key-auth creds,
-- and an entry in consumers_rbac_users_map for every rbac_user in the
-- database. Going forward, we leave existing rbac_users as is and
-- provide a default user for Kong Manager that can be used to log in
-- and create other users.
return {
  admins = {
    {
      name = "2018-06-30-000000_rbac_consumer_admins",
      up = function (_, _, dao)
      end
    }
  }
}
