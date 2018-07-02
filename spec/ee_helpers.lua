local _M = {}


function _M.register_rbac_resources(dao)
  local utils = require "kong.tools.utils"
  local bit   = require "bit"
  local rbac  = require "kong.rbac"
  local bxor  = bit.bxor

  -- action int for all
  local action_bits_all = 0x0
  for k, v in pairs(rbac.actions_bitfields) do
    action_bits_all = bxor(action_bits_all, rbac.actions_bitfields[k])
  end

  local roles = {}

  -- now, create the roles and assign endpoint permissions to them

  -- first, a read-only role across everything
  roles.read_only = dao.rbac_roles:insert({
    id = utils.uuid(),
    name = "read-only",
    comment = "Read-only access across all initial RBAC resources",
  })
  -- this role only has the 'read-only' permissions
  dao.rbac_role_endpoints:insert({
    role_id = roles.read_only.id,
    workspace = "*",
    endpoint = "*",
    actions = rbac.actions_bitfields.read,
  })

  -- admin role with CRUD access to all resources except RBAC resource
  roles.admin = dao.rbac_roles:insert({
    id = utils.uuid(),
    name = "admin",
    comment = "CRUD access to most initial resources (no RBAC)",
  })

  -- the 'admin' role has 'full-access' + 'no-rbac' permissions
  dao.rbac_role_endpoints:insert({
    role_id = roles.admin.id,
    workspace = "*",
    endpoint = "*",
    actions = action_bits_all, -- all actions
  })

  dao.rbac_role_endpoints:insert({
    role_id = roles.admin.id,
    workspace = "*",
    endpoint = "/rbac",
    negative = true,
    actions = action_bits_all, -- all actions
  })

  -- finally, a super user role who has access to all initial resources
  roles.super_admin = dao.rbac_roles:insert({
    id = utils.uuid(),
    name = "super-admin",
    comment = "Full CRUD access to all initial resources, including RBAC entities",
  })

  dao.rbac_role_endpoints:insert({
    role_id = roles.super_admin.id,
    workspace = "*",
    endpoint = "*",
    actions = action_bits_all, -- all actions
  })

  local super_admin, err = dao.rbac_users:insert({
    id = utils.uuid(),
    name = "super_gruce",
    user_token = "letmein",
    enabled = true,
    comment = "Test - Initial RBAC Super Admin User"
  })

  if err then
    return err
  end

  local super_user_role, err = dao.rbac_user_roles:insert({
    user_id = super_admin.id,
    role_id = roles.super_admin.id
  })

  if err then
    return err
  end

  return super_admin, super_user_role
end


return _M
