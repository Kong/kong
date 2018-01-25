local crud      = require "kong.api.crud_helpers"
local utils     = require "kong.tools.utils"
local rbac      = require "kong.rbac"
local bit       = require "bit"
local cjson     = require "cjson"
local responses = require "kong.tools.responses"
local new_tab   = require "table.new"


local band  = bit.band
local bxor  = bit.bxor
local fmt   = string.format


local entity_relationships = rbac.entity_relationships


local function objects_from_names(dao_factory, given_names, object_name)
  local names      = utils.split(given_names, ",")
  local objs       = new_tab(#names, 0)
  local object_dao = fmt("rbac_%ss", object_name)

  for i = 1, #names do
    local object, err = dao_factory[object_dao]:find_all({
      name = names[i],
    })
    if err then
      return nil, err
    end

    if not object[1] then
      return nil, fmt("%s not found with name '%s'", object_name, names[i])
    end

    -- track the whole object so we have the id for the mapping later
    objs[i] = object[1]
  end

  return objs
end

local function action_bitfield(self)
  local action_bitfield = 0x0

  if type(self.params.actions) == "string" then
    local action_names = utils.split(self.params.actions, ",")

    for i = 1, #action_names do
      local action = action_names[i]

      -- keyword all sets everything
      if action == "all" then
        for k in pairs(rbac.actions_bitfields) do
          action_bitfield = bxor(action_bitfield, rbac.actions_bitfields[k])
        end

        break
      end

      if not rbac.actions_bitfields[action] then
        return responses.send_HTTP_BAD_REQUEST("Undefined RBAC action " ..
                                               action_names[i])
      end

      action_bitfield = bxor(action_bitfield, rbac.actions_bitfields[action])
    end
  end

  self.params.actions = action_bitfield
end

local function resource_bitfield(self)
  local bitfield = 0x0

  if type(self.params.resources) == "string" then
    local resources_names = utils.split(self.params.resources, ",")

    for i = 1, #resources_names do
      local resource = resources_names[i]

      -- keyword all sets everything
      if resource == "all" then
        for i, _ in ipairs(rbac.resource_bitfields) do
          bitfield = bxor(bitfield, 2 ^ (i - 1))
        end

        break
      end

      if not rbac.resource_bitfields[resource] then
        return responses.send_HTTP_BAD_REQUEST("Undefined RBAC action " ..
                                               resource)
      end

      bitfield = bxor(bitfield, rbac.resource_bitfields[resource])
    end
  end

  self.params.resources = bitfield
end

local function readable_actions(permission)
  local action_t     = setmetatable({}, cjson.empty_array_mt)
  local action_t_idx = 0

  for k in pairs(rbac.actions_bitfields) do
    local n = rbac.actions_bitfields[k]

    if band(n, permission.actions) == n then
      action_t_idx = action_t_idx + 1
      action_t[action_t_idx] = k
    end
  end

  permission.actions = action_t
end

local function readable_resources(permission)
  local resource_t     = setmetatable({}, cjson.empty_array_mt)
  local resource_t_idx = 0

  for i, _ in ipairs(rbac.resource_bitfields) do
    local k = rbac.resource_bitfields[i]
    local n = rbac.resource_bitfields[k]

    if band(n, permission.resources) == n then
      resource_t_idx = resource_t_idx + 1
      resource_t[resource_t_idx] = k
    end
  end

  permission.resources = resource_t
end


local function post_process_actions(row)
  local actions_t = setmetatable({}, cjson.empty_array_mt)
  local actions_t_idx = 0


  for k, n in pairs(rbac.actions_bitfields) do
    if band(n, row.actions) == n then
      actions_t_idx = actions_t_idx + 1
      actions_t[actions_t_idx] = k
    end
  end


  row.actions = actions_t
  return row
end


return {
  ["/rbac/users/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.rbac_users)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.rbac_users)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.rbac_users)
    end,
  },

  ["/rbac/users/:name_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_user_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.rbac_user)
    end,

    PATCH = function(self, dao_factory, helpers)
      crud.patch(self.params, dao_factory.rbac_users, self.rbac_user)
    end,

    DELETE = function(self, dao_factory, helpers)
      -- delete the user <-> role mappings
      -- we have to get our row, then delete it
      local roles, err = entity_relationships(dao_factory, self.rbac_user,
                                              "user", "role")
      if err then
        return helpers.yield_error(err)
      end

      for i = 1, #roles do
        dao_factory.rbac_user_roles:delete({
          user_id = self.rbac_user.id,
          role_id = roles[i].id,
        })
      end

      crud.delete(self.rbac_user, dao_factory.rbac_users)
    end,
  },

  ["/rbac/users/:name_or_id/permissions"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_user_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local map = rbac.build_permissions_map(self.rbac_user, dao_factory)

      for action, value in pairs(map) do
        local action_t = {}
        for k in pairs(rbac.actions_bitfields) do
          local n = rbac.actions_bitfields[k]

          if band(n, value) == n then
            action_t[#action_t + 1] = k
          end
        end
        map[action] = #action_t > 0 and action_t or nil
      end

      return helpers.responses.send_HTTP_OK(map)
    end,
  },

  ["/rbac/users/:name_or_id/roles"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_user_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local roles, err = entity_relationships(dao_factory, self.rbac_user,
                                              "user", "role")
      if err then
        return helpers.yield_error(err)
      end

      setmetatable(roles, cjson.empty_array_mt)
      return helpers.responses.send_HTTP_OK({
        user  = self.rbac_user,
        roles = roles,
      })
    end,

    POST = function(self, dao_factory, helpers)
      -- we have the user, now verify our roles
      if not self.params.roles then
        return helpers.responses.send_HTTP_BAD_REQUEST("must provide >= 1 role")
      end

      local roles, err = objects_from_names(dao_factory, self.params.roles,
                                            "role")
      if err then
        if err:find("not found with name", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          return helpers.yield_error(err)
        end
      end

      -- we've now validated that all our roles exist, and this user exists,
       -- so time to create the assignment
      for i = 1, #roles do
        local _, err = dao_factory.rbac_user_roles:insert({
          user_id = self.rbac_user.id,
          role_id = roles[i].id
        })
        if err then
          return helpers.yield_error(err)
        end
      end

      -- re-fetch the users roles so we show all the role objects, not just our
      -- newly assigned mappings
      roles, err = entity_relationships(dao_factory, self.rbac_user,
                                        "user", "role")
      if err then
        return helpers.yield_error(err)
      end

      -- show the user and all of the roles they are in
      return helpers.responses.send_HTTP_CREATED({
        user  = self.rbac_user,
        roles = roles,
      })
    end,

    DELETE = function(self, dao_factory, helpers)
      -- we have the user, now verify our roles
      if not self.params.roles then
        return helpers.responses.send_HTTP_BAD_REQUEST("must provide >= 1 role")
      end

      local roles, err = objects_from_names(dao_factory, self.params.roles,
                                            "role")
      if err then
        if err:find("not found with name", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          return helpers.yield_error(err)
        end
      end

      for i = 1, #roles do
        dao_factory.rbac_user_roles:delete({
          user_id = self.rbac_user.id,
          role_id = roles[i].id,
        })
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },

  ["/rbac/roles"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.rbac_roles)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.rbac_roles)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.rbac_roles)
    end,
  },

  ["/rbac/roles/:name_or_id"] = {
    resource = "rbac",

    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.rbac_role)
    end,

    PATCH = function(self, dao_factory, helpers)
      crud.patch(self.params, dao_factory.rbac_roles, self.rbac_role)
    end,

    DELETE = function(self, dao_factory, helpers)
      -- delete the user <-> role mappings
      -- we have to get our row, then delete it
      local users, err = entity_relationships(dao_factory, self.rbac_role,
                                              "user", "role")
      if err then
        return helpers.yield_error(err)
      end

      for i = 1, #users do
        dao_factory.rbac_user_roles:delete({
          user_id = users[i].id,
          role_id = self.rbac_role.id,
        })
      end

      -- delete the role <-> permission mappings
      -- we have to get our row, then delete it
      local perms, err = entity_relationships(dao_factory, self.rbac_role,
                                              "role", "perm")
      if err then
        return helpers.yield_error(err)
      end

      for i = 1, #perms do
        dao_factory.rbac_role_perms:delete({
          role_id = self.rbac_role.id,
          perm_id = perms[i].id
        })
      end

      crud.delete(self.rbac_role, dao_factory.rbac_roles)
    end,
  },

  ["/rbac/roles/:name_or_id/permissions"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local p, err = entity_relationships(dao_factory, self.rbac_role,
                                          "role", "perm")
      if err then
        return helpers.yield_error(err)
      end

      local perms = utils.deep_copy(p)
      setmetatable(perms, cjson.empty_array_mt)

      for i = 1, #perms do
        readable_actions(perms[i])
        readable_resources(perms[i])
      end

      return helpers.responses.send_HTTP_OK({
        role  = self.rbac_role,
        permissions = perms,
      })
    end,

    POST = function(self, dao_factory, helpers)
      -- we have the role, now verify our permissions
      if not self.params.permissions then
        return helpers.responses.send_HTTP_BAD_REQUEST("must provide >= 1 permission")
      end

      local perms, err = objects_from_names(dao_factory, self.params.permissions,
                                            "perm")
      if err then
        if err:find("not found with name", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          return helpers.yield_error(err)
        end
      end

      -- we've now validated that all our perms exist, and this role exists,
      -- so time to create the assignment
      for i = 1, #perms do
        local _, err = dao_factory.rbac_role_perms:insert({
          role_id = self.rbac_role.id,
          perm_id = perms[i].id
        })
        if err then
          return helpers.yield_error(err)
        end
      end

      -- re-fetch the users perms so we show all the permissions objects,
      -- not just our newly assigned mappings
      local p, err = entity_relationships(dao_factory, self.rbac_role,
                                          "role", "perm")
      if err then
        return helpers.yield_error(err)
      end

      perms = utils.deep_copy(p)

      for i = 1, #perms do
        readable_actions(perms[i])
        readable_resources(perms[i])
      end

      -- show the user and all of the roles they are in
      return helpers.responses.send_HTTP_CREATED({
        role = self.rbac_role,
        permissions = perms,
      })
    end,

    DELETE = function(self, dao_factory, helpers)
      -- we have the role, now verify our permissions
      if not self.params.permissions then
        return helpers.responses.send_HTTP_BAD_REQUEST("must provide >= 1 permission")
      end

      local perms, err = objects_from_names(dao_factory, self.params.permissions,
                                            "perm")
      if err then
        if err:find("not found with name", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          return helpers.yield_error(err)
        end
      end

      for i = 1, #perms do
        dao_factory.rbac_role_perms:delete({
          role_id = self.rbac_role.id,
          perm_id = perms[i].id,
        })
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },

  ["/rbac/permissions"] = {
    GET = function(self, dao_factory, helpers)
      local dao_collection = dao_factory.rbac_perms

      local size = self.params.size and tonumber(self.params.size) or 100
      local offset = self.params.offset and ngx.decode_base64(self.params.offset)

      self.params.size = nil
      self.params.offset = nil

      local filter_keys = next(self.params) and self.params

      local r, err, offset = dao_collection:find_page(filter_keys, offset, size)
      if err then
        return helpers.yield_error(err)
      end

      local total_count, err = dao_collection:count(filter_keys)
      if err then
        return helpers.yield_error(err)
      end

      local next_url
      if offset then
        offset = ngx.encode_base64(offset)
        next_url = self:build_url(self.req.parsed_url.path, {
          port = self.req.parsed_url.port,
          query = ngx.encode_args {
            offset = offset,
            size = size
          }
        })
      end

      local rows = utils.deep_copy(r)

      for i = 1, #rows do
        readable_actions(rows[i])
        readable_resources(rows[i])
      end

      return helpers.responses.send_HTTP_OK {
        data = #rows > 0 and rows or cjson.empty_array,
        total = total_count,
        offset = offset,
        ["next"] = next_url
      }
    end,

    POST = function(self, dao_factory, helpers)
      action_bitfield(self)
      resource_bitfield(self)

      local p, err = dao_factory.rbac_perms:insert(self.params)
      if err then
        return helpers.yield_error(err)
      end

      local permission = utils.deep_copy(p)

      readable_actions(permission)
      readable_resources(permission)

      return helpers.responses.send_HTTP_CREATED(permission)
    end,

    PUT = function(self, dao_factory)
      action_bitfield(self)
      resource_bitfield(self)

      crud.put(self.params, dao_factory.rbac_perms)
    end,
  },

  ["/rbac/permissions/:name_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_perm_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local permission, err = dao_factory.rbac_perms:find(self.rbac_perm)
      if err then
        return helpers.yield_error(err)
      end

      if not permission then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      readable_actions(permission)
      readable_resources(permission)

      return helpers.responses.send_HTTP_OK(permission)
    end,

    PATCH = function(self, dao_factory, helpers)
      action_bitfield(self)
      resource_bitfield(self)

      local p, err = dao_factory.rbac_perms:update(self.params,
                                                            self.rbac_perm)
      if err then
        return helpers.yeild_error(err)
      end

      local permission = utils.deep_copy(p)

      readable_actions(permission)
      readable_resources(permission)

      return helpers.responses.send_HTTP_OK(permission)
    end,

    DELETE = function(self, dao_factory, helpers)
      -- delete the role <-> permission mappings
      -- we have to get our row, then delete it
      local roles, err = entity_relationships(dao_factory, self.rbac_perm,
                                              "role", "perm")
      if err then
        return helpers.yield_error(err)
      end

      for i = 1, #roles do
        dao_factory.rbac_role_perms:delete({
          role_id = roles[i].id,
          perm_id = self.rbac_perm.id
        })
      end

      crud.delete(self.rbac_perm, dao_factory.rbac_perms)
    end,
  },

  ["/rbac/resources"] = {
    GET = function(self, dao_factory, helpers)
      local resources = {}

      for k in pairs(rbac.resource_routes) do
        resources[#resources + 1] = k
      end

      return helpers.responses.send_HTTP_OK(resources)
    end,
  },

  ["/rbac/resources/routes"] = {
    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(rbac.route_resources)
    end,
  },

  ["/rbac/roles/:name_or_id/entities"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
      self.params.role_id = self.rbac_role.id
    end,

    GET = function(self, dao_factory, helpers)
      return crud.paginated_set(self, dao_factory.role_entities,
                                post_process_actions)
    end,

    POST = function(self, dao_factory, helpers)
      action_bitfield(self)

      local is_workspace, err = dao_factory.workspaces:find_all({
        id = self.params.entity_id,
      })
      if err then
        helpers.yield_error(err)
      end
      is_workspace = is_workspace[1] and true or false

      if is_workspace then
        self.params.entity_type = "workspace"
      else
        self.params.entity_type = "entity"
      end

      crud.post(self.params, dao_factory.role_entities,
                post_process_actions)
    end,
  },

  ["/rbac/roles/:name_or_id/entities/:entity_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
      self.params.role_id = self.rbac_role.id
    end,

    GET = function(self, dao_factory, helpers)
      crud.get(self.params, dao_factory.role_entities,
               post_process_actions)
    end,

    PATCH = function(self, dao_factory, helpers)
      if self.params.actions then
        action_bitfield(self)
      end

      local filter = {
        role_id = self.params.role_id,
        entity_id = self.params.entity_id,
      }

      self.params.role_id = nil
      self.params.entity_id = nil

      crud.patch(self.params, dao_factory.role_entities, filter,
                 post_process_actions)
    end,

    DELETE = function(self, dao_factory, helpers)
      crud.delete(self.params, dao_factory.role_entities)
    end,
  },

  ["/rbac/roles/:name_or_id/entities/permissions"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local map = rbac.resolve_role_entity_permissions({ self.rbac_role })

      for k, v in pairs(map) do
        local actions_t = setmetatable({}, cjson.empty_array_mt)
        local actions_t_idx = 0

        for action, n in pairs(rbac.actions_bitfields) do
          if band(n, v) == n then
            actions_t_idx = actions_t_idx + 1
            actions_t[actions_t_idx] = action
          end
        end

        map[k] = actions_t
      end

      return helpers.responses.send_HTTP_OK(map)
    end,
  },

  ["/rbac/roles/:name_or_id/endpoints"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
      self.params.role_id = self.rbac_role.id
    end,

    GET = function(self, dao_factory, helpers)
      return crud.paginated_set(self, dao_factory.role_endpoints,
                                post_process_actions)
    end,

    POST = function(self, dao_factory, helpers)
      action_bitfield(self)

      local w, err = dao_factory.workspaces:find_all({
        name = self.params.workspace
      })
      if err then
        helpers.yield_error(err)
      end

      if #w == 0 then
        helpers.responses.send_HTTP_NOT_FOUND("Workspace '" ..
                                              self.params.workspace .. "' " ..
                                              "does not exist")
      end

      crud.post(self.params, dao_factory.role_endpoints,
                post_process_actions)
    end,
  },

  ["/rbac/roles/:name_or_id/endpoints/:workspace/:endpoint"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
      self.params.role_id = self.rbac_role.id
    end,

    GET = function(self, dao_factory, helpers)
      crud.get(self.params, dao_factory.role_endpoints,
               post_process_actions)
    end,

    PATCH = function(self, dao_factory, helpers)
      if self.params.actions then
        action_bitfield(self)
      end

      local filter = {
        role_id = self.params.role_id,
        workspace = self.params.workspace,
        endpoint = self.params.endpoint,
      }

      self.params.role_id = nil
      self.params.workspace = nil
      self.params.endpoint = nil

      crud.patch(self.params, dao_factory.role_endpoints, filter,
                 post_process_actions)
    end,

    DELETE = function(self, dao_factory, helpers)
      crud.delete(self.params, dao_factory.role_endpoints)
    end,
  },

  ["/rbac/roles/:name_or_id/endpoints/permissions"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local map = rbac.resolve_role_endpoint_permissions({ self.rbac_role })

      for workspace in pairs(map) do
        for endpoint, actions in pairs(map[workspace]) do
          local actions_t = setmetatable({}, cjson.empty_array_mt)
          local actions_t_idx = 0

          for action, n in pairs(rbac.actions_bitfields) do
            if band(n, actions) == n then
              actions_t_idx = actions_t_idx + 1
              actions_t[actions_t_idx] = action
            end
          end

          map[workspace][endpoint] = actions_t
        end
      end

      return helpers.responses.send_HTTP_OK(map)
    end,
  },
}
