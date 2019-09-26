local endpoints          = require "kong.api.endpoints"
local utils              = require "kong.tools.utils"
local workspaces         = require "kong.workspaces"

local groups             = kong.db.groups
local group_rbac_roles   = kong.db.group_rbac_roles
local rbac_roles         = kong.db.rbac_roles

local function response_filter(group, role, workspace)
  if group.created_at then
    group.created_at = nil
  end

  return {
    group = group,
    rbac_role = {
      id = role.id,
      name = role.name,
    },
    workspace = {
      id = workspace.id
    },
  }
end

local function post_process_action(row)
  local rbac_role_row, err_role = rbac_roles:select({ id = row.rbac_role.id })
  local group_row, err_group = groups:select({ id = row.group.id })

  if err_role or err_group then
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if not rbac_role_row or not group_row then
    return kong.response.exit(404, { message = "Not found" })
  end

  return response_filter(group_row, rbac_role_row, { id = row.workspace.id })
end

return {
  ["/groups"] = {
    GET = function(self, db, helpers)
      return endpoints.get_collection_endpoint(groups.schema)
                                              (self, db, helpers)
    end,

    POST = function(self, db, helpers)
      return endpoints.post_collection_endpoint(groups.schema)(self, db, helpers)
    end,
  },

  ["/groups/:groups"] = {
    GET    = endpoints.get_entity_endpoint(groups.schema),

    PATCH  = endpoints.patch_entity_endpoint(groups.schema),

    DELETE = function(self, db, helpers)
      local _, err_t

      if not utils.is_valid_uuid(self.params.groups) then
        _, _, err_t = groups:delete_by_name(self.params.groups)
      else
        _, _, err_t = groups:delete({ id = self.params.groups })
      end

      if err_t then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(204)
    end,
  },

  ["/groups/:groups/roles"] = {
    before = function(self, db, helpers)
      if self.req.cmd_mth == "POST" or self.req.cmd_mth == "DELETE" then
        local entity, _, err_t

        if not utils.is_valid_uuid(self.params.groups) then
          entity, _, err_t = groups:select_by_name(self.params.groups)
        else
          entity, _, err_t = groups:select({ id = self.params.groups })
        end

        if err_t then
          return endpoints.handle_error(err_t)
        end

        if not entity then
          return kong.response.exit(404, { message = "Not found" })
        end

        self.params.groups = entity
      end
    end,

    GET = function(self, db, helpers)
      workspaces.run_with_ws_scope({}, function()
          return endpoints.get_collection_endpoint(group_rbac_roles.schema,
                                               groups.schema, "group")
                                              (self, db, helpers,
                                               post_process_action)
      end)
    end,

    POST = function(self, db, helpers)
      local entities = {}
      local check_list = {
        rbac_roles = "rbac_role_id",
        workspaces = "workspace_id",
      }

      -- verify params and entities
      for schema, key in pairs(check_list) do
        if not self.params[key] then
          return kong.response.exit(400, { message = "must provide the " .. key })
        end

        entities[schema] = workspaces.run_with_ws_scope(
          -- ws_scope is a ws array
          {{ id = self.params.workspace_id }},
          db[schema].select, db[schema],
          { id = self.params[key] }
        )

        if not entities[schema] then
          return kong.response.exit(404, { message = "Not found" })
        end
      end

      local cache_key = db["group_rbac_roles"]:cache_key(self.params.groups.id)
      kong.cache:invalidate(cache_key)

      workspaces.run_with_ws_scope({{ id = self.params.workspace_id }}, function()
          local _, _, err_t = group_rbac_roles:insert({
            rbac_role = { id = self.params.rbac_role_id },
            workspace = { id = self.params.workspace_id },
            group 	  = { id = self.params.groups.id },
          })

          if err_t then
            return endpoints.handle_error(err_t)
          end
      end)

      return kong.response.exit(201, response_filter(
        self.params.groups,
        entities.rbac_roles,
        entities.workspaces
      ))
    end,

    DELETE = function(self, db, helpers)
      local check_list = {
        rbac_roles = "rbac_role_id",
        workspaces = "workspace_id",
      }

      for schema, key in pairs(check_list) do
        if not self.params[key] then
          return kong.response.exit(400, { message = "must provide the " .. key })
        end
      end

      local cache_key = db["group_rbac_roles"]:cache_key(self.params.groups.id)
      kong.cache:invalidate(cache_key)

      workspaces.run_with_ws_scope({{ id = self.params.workspace_id }}, function()
          local _, err = group_rbac_roles:delete({
            rbac_role = { id = self.params.rbac_role_id },
            group 	  = { id = self.params.groups.id },
          })
          
          if err then
            kong.log.err('DELETE /groups/:groups/roles:', err)
          end
      end)

      return kong.response.exit(204)
    end,
  },
}
