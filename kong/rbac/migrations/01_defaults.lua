local utils = require "kong.tools.utils"
local rbac = require "kong.rbac"
local bor = bit.bor

return {
  up = function (_, _, dao)
      local role, ok, err


      role, err = dao.rbac_roles:find_all({
        name = "read-only"
      })
      if err then
        return err
      end
      role = role[1]
      if not role then
        -- create read only role
        role, err = dao.rbac_roles:insert({
          id = utils.uuid(),
          name = "read-only",
          comment = "Read access to all endpoints, across all workspaces",
        })
        if err then
          return err
        end
      end

      -- add endpoint permissions to the read only role
      ok, err = dao.rbac_role_endpoints:insert({
        role_id = role.id,
        workspace = "*",
        endpoint = "*",
        actions = rbac.actions_bitfields.read,
      })
      if not ok then
        return err
      end

      role, err = dao.rbac_roles:find_all({name = "admin"})
      if err then
        return err
      end
      role = role[1]
      if not role then
        -- create admin role
        role, err = dao.rbac_roles:insert({
          id = utils.uuid(),
          name = "admin",
          comment = "Full access to all endpoints, across all workspaces - except RBAC Admin API",
        })
        if err then
          return err
        end
      end

      local action_bits_all = 0x0
      for k, v in pairs(rbac.actions_bitfields) do
        action_bits_all = bor(action_bits_all, rbac.actions_bitfields[k])
      end

      -- add endpoint permissions to the admin role
      ok, err = dao.rbac_role_endpoints:insert({
        role_id = role.id,
        workspace = "*",
        endpoint = "*",
        actions = action_bits_all, -- all actions
      })
      if not ok then
        return err
      end

      -- add negative endpoint permissions to the rbac endpoint
      ok, err = dao.rbac_role_endpoints:insert({
        role_id = role.id,
        workspace = "*",
        endpoint = "/rbac",
        negative = true,
        actions = action_bits_all, -- all actions
      })
      if not ok then
        return err
      end

      role, err = dao.rbac_roles:find_all({name = "super-admin"})
      if err then
        return err
      end
      role = role[1]
      if not role then
        -- create super admin role
        role, err = dao.rbac_roles:insert({
          id = utils.uuid(),
          name = "super-admin",
          comment = "Full access to all endpoints, across all workspaces",
        })
        if err then
          return err
        end
      end



      -- add endpoint permissions to the super admin role
      ok, err = dao.rbac_role_endpoints:insert({
        role_id = role.id,
        workspace = "*",
        endpoint = "*",
        actions = action_bits_all, -- all actions
      })
      if not ok then
        return err
      end
  end
}
