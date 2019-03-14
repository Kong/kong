local utils = require "kong.tools.utils"
local rbac = require "kong.rbac"
local bor = bit.bor

return {
  up = function (_, _, dao)
      local role, ok, err


      role, err = dao.rbac_roles:select_by_name("read-only")
      if err then
        return err
      end
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

      role, err = dao.rbac_roles:select_by_name("admin")
      if err then
        return err
      end
      if not role then
        -- create admin role
        role, err = dao.rbac_roles:insert({
          id = utils.uuid(),
          name = "admin",
          comment = "Full access to all endpoints, across all workspaces—except RBAC Admin API",
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

      -- for each possible rbac endpoint, register a negative
      -- permission
      -- yes, this is ugly, but we do not support a generic
      -- wildcard with prefix matching - instead, wildcards
      -- are for path segments (/*/)
      for _, rbac_endpoint in ipairs{
        "/rbac/*",
        "/rbac/*/*",
        "/rbac/*/*/*",
        "/rbac/*/*/*/*",
        "/rbac/*/*/*/*/*",
      } do
        -- add negative endpoint permissions to the rbac endpoint
        ok, err = dao.rbac_role_endpoints:insert({
          role_id = role.id,
          workspace = "*",
          endpoint = rbac_endpoint,
          negative = true,
          actions = action_bits_all, -- all actions
        })
        if not ok then
          return err
        end
      end

      role, err = dao.rbac_roles:select_by_name("superadmin")
      if err then
        return err
      end
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

      ok, err = dao.rbac_role_entities:insert({
        role_id = role.id,
        entity_id = "*",
        entity_type = "wildcard",
        actions = action_bits_all,
      })
      if not ok then
        return err
      end
  end
}
