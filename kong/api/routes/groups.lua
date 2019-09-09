local endpoints        = require "kong.api.endpoints"

local fmt              = string.format
local groups           = kong.db.groups
local group_rbac_roles = kong.db.group_rbac_roles
local rbac_roles       = kong.db.rbac_roles

local function retrieve_entity(dao, id)
  local entity, err = dao:select({ id = id })

  if not entity then
    return kong.response.exit(500, err)
  end

  return entity
end

local function select_from_cache(dao, id)
  local cache_key = dao:cache_key(id)
  local entity, err = kong.cache:get(cache_key, nil, retrieve_entity, dao, id)

  if not entity then
    return kong.response.exit(500, err)
  end

  return entity
end

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
    }
  }
end

local function post_process_action(row)
  local _rbac_role = select_from_cache(rbac_roles, row.rbac_role.id)
  
  row.group = select_from_cache(groups, row.group.id)
  
  return response_filter(row.group, _rbac_role, { id = row.workspace.id })
end

return {
  ["/groups"] = {
    GET = function(self, db, helpers) 
      return endpoints.get_collection_endpoint(groups.schema)
                                              (self, db, helpers,
                                               nil, "/groups")
    end,

    POST = function(self, db, helpers)
      return endpoints.post_collection_endpoint(groups.schema)(self, db, helpers)
    end,
  },

  ["/groups/:groups"] = {
    PATCH = endpoints.patch_entity_endpoint(groups.schema),
  },

  ["/groups/:groups/roles"] = {
    GET = function(self, db, helpers)
      local next_page = fmt("/groups/%s/roles", self.params.groups)

      return endpoints.get_collection_endpoint(group_rbac_roles.schema,
                                               groups.schema, "group")
                                              (self, db, helpers,
                                               post_process_action,
                                               next_page)
    end,

    POST = function(self, db, helpers)
      local entities = {}
      local check_list = {
        groups     = "groups",
        rbac_roles = "rbac_role_id",
        workspaces = "workspace_id",
      }

      -- verify params and entities
      for schema, key in pairs(check_list) do
        if not self.params[key] then
          return kong.response.exit(400, "must provide the " .. key)
        end

        entities[schema] = db[schema]:select({ id = self.params[key] })
        if not entities[schema] then
          return kong.response.exit(404, { message = "Not found" })
        end
      end

      local row, err = group_rbac_roles:insert({
        rbac_role = { id = self.params.rbac_role_id },
        workspace = { id = self.params.workspace_id },
        group 	  = { id = self.params.groups },
      })

      if not row then
        return kong.response.exit(500, { message = err })
      end

      return kong.response.exit(201, response_filter(
        entities.groups, 
        entities.rbac_roles,
        entities.workspaces
      ))
    end,

    DELETE = function(self, db, helpers)
      local check_list = {
        groups     = "groups",
        rbac_roles = "rbac_role_id",
        workspaces = "workspace_id",
      }

      for schema, key in pairs(check_list) do
        if not self.params[key] then
          return kong.response.exit(400, "must provide the " .. key)
        end
      end

      group_rbac_roles:delete({
        rbac_role = { id = self.params.rbac_role_id },
        group 	  = { id = self.params.groups },
      })

      return kong.response.exit(204)
    end,
  },
}
