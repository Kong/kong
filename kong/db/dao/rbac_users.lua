local rbac_users = {}


function rbac_users:cache_key(id)
  if type(id) == "table" then
    id = id.id
  end

  -- Always return the cache_key without a workspace
  return "rbac_users:" .. id .. ":::::"
end


return rbac_users
