local crud      = require "kong.api.crud_helpers"
local utils     = require "kong.tools.utils"
local rbac      = require "kong.rbac"
local bit       = require "bit"
local cjson     = require "cjson"
local responses = require "kong.tools.responses"
local new_tab   = require "table.new"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"
local tablex     = require "pl.tablex"


local band  = bit.band
local bxor  = bit.bxor
local fmt   = string.format


local entity_relationships = rbac.entity_relationships


local function rbac_operation_allowed(kong_conf, rbac_ctx, current_ws, dest_ws)
  if kong_conf.rbac == "off" then
    return true
  end

  if current_ws == dest_ws then
    return true
  end

  -- dest is different from current
  if rbac.user_can_manage_endpoints_from(rbac_ctx, dest_ws) then
    return true
  end

  return false
end


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
      if action == "*" then
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


local function post_process_role(role)
  -- don't expose column that is for internal use only
  role.is_default = nil
  return role
end


return {
  ["/rbac/users/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.rbac_users)
    end,

    POST = function(self, dao_factory, helpers)
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

      local default_role

      for i = 1, #roles do
        dao_factory.rbac_user_roles:delete({
          user_id = self.rbac_user.id,
          role_id = roles[i].id,
        })

        if roles[i].name == self.rbac_user.name then
          default_role = roles[i]
        end
      end

      if default_role then
        local _, err = rbac.remove_user_from_default_role(self.rbac_user,
                                                          default_role)
        if err then
          helpers.yield_error(err)
        end
      end

      crud.delete(self.rbac_user, dao_factory.rbac_users)
    end,
  },

  ["/rbac/users/:name_or_id/permissions"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_user_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local roles, err = rbac.entity_relationships(dao_factory, self.rbac_user,
                                                   "user", "role")
      if err then
        ngx.log(ngx.ERR, "[rbac] ", err)
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
      end

      local map = {}
      local entities_perms = rbac.readable_entities_permissions(roles)
      local endpoints_perms = rbac.readable_endpoints_permissions(roles)

      map.entities = entities_perms
      map.endpoints = endpoints_perms

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

      -- filter out default roles and suppress the is_default column
      roles = tablex.filter(roles, function(role) return not role.is_default end)

      for _, role in ipairs(roles) do
        post_process_role(role)
      end

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

      -- invalidate rbac user so we don't fetch the old roles
      local cache_key = dao_factory["rbac_user_roles"]:cache_key(self.rbac_user.id)
      singletons.cache:invalidate(cache_key)

      -- re-fetch the users roles so we show all the role objects, not just our
      -- newly assigned mappings
      roles, err = entity_relationships(dao_factory, self.rbac_user,
                                        "user", "role")
      if err then
        return helpers.yield_error(err)
      end

      -- filter out default roles and suppress the is_default column
      roles = tablex.filter(roles, function(role) return not role.is_default end)

      for _, role in ipairs(roles) do
        post_process_role(role)
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

      local cache_key = dao_factory["rbac_users"]:cache_key(self.rbac_user.id)
      singletons.cache:invalidate(cache_key)

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },

  ["/rbac/roles"] = {
    GET = function(self, dao_factory)
      self.params["is_default"] = false
      crud.paginated_set(self, dao_factory.rbac_roles, post_process_role)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.rbac_roles)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.rbac_roles)
    end,
  },

  ["/rbac/roles/:name_or_id/permissions"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local map = {}
      local entities_perms = rbac.readable_entities_permissions({self.rbac_role})
      local endpoints_perms = rbac.readable_endpoints_permissions({self.rbac_role})

      map.entities = entities_perms
      map.endpoints = endpoints_perms

      return helpers.responses.send_HTTP_OK(map)
    end,
  },

  ["/rbac/roles/:name_or_id"] = {
    before = function(self, dao_factory, helpers)
      self.params["is_default"] = false
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(post_process_role(self.rbac_role))
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

      local err = rbac.role_relation_cleanup(self.rbac_role)
      if err then
        return nil, err
      end

      crud.delete(self.rbac_role, dao_factory.rbac_roles)
    end,
  },

   ["/rbac/roles/:name_or_id/entities"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
      self.params.role_id = self.rbac_role.id
    end,

    GET = function(self, dao_factory, helpers)
      return crud.paginated_set(self, dao_factory.rbac_role_entities,
                                post_process_actions)
    end,

    POST = function(self, dao_factory, helpers)
      action_bitfield(self)

      if not self.params.entity_id then
        return helpers.responses.send_HTTP_BAD_REQUEST("Missing required parameter: 'entity_id'")
      end

      local entity_type = "wildcard"
      if self.params.entity_id ~= "*" then
        local _, err
        entity_type, _, err = workspaces.resolve_entity_type(self.params.entity_id)
        -- database error
        if entity_type == nil then
          return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
        end
        -- entity doesn't exist
        if entity_type == false then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)
        end
      end

      self.params.entity_type = entity_type
      crud.post(self.params, dao_factory.rbac_role_entities,
                post_process_actions)
    end,
  },

  ["/rbac/roles/:name_or_id/entities/:entity_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
      self.params.role_id = self.rbac_role.id
      if self.params.entity_id ~= "*" and not utils.is_valid_uuid(self.params.entity_id) then
        return helpers.responses.send_HTTP_BAD_REQUEST(
          self.params.entity_id .. " is not a valid uuid")
      end
    end,

    GET = function(self, dao_factory, helpers)
      crud.get(self.params, dao_factory.rbac_role_entities,
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

      crud.patch(self.params, dao_factory.rbac_role_entities, filter,
                 post_process_actions)
    end,

    DELETE = function(self, dao_factory, helpers)
      crud.delete(self.params, dao_factory.rbac_role_entities)
    end,
  },

  ["/rbac/roles/:name_or_id/entities/permissions"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local map = rbac.readable_entities_permissions({self.rbac_role})
      return helpers.responses.send_HTTP_OK(map)
    end,
  },

  ["/rbac/roles/:name_or_id/endpoints"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
      self.params.role_id = self.rbac_role.id
    end,

    GET = function(self, dao_factory, helpers)
      return crud.paginated_set(self, dao_factory.rbac_role_endpoints,
                                post_process_actions)
    end,

    POST = function(self, dao_factory, helpers)
      action_bitfield(self)
      if not self.params.endpoint then
        helpers.responses.send_HTTP_BAD_REQUEST("'endpoint' is a required field")
      end

      local ctx = ngx.ctx
      local request_ws = ctx.workspaces[1]

      -- if the `workspace` parameter wasn't passed, fallback to the current
      -- request's workspace
      self.params.workspace = self.params.workspace or request_ws.name

      local ws_name = self.params.workspace

      if ws_name ~= "*" then
        local w, err = dao_factory.workspaces:run_with_ws_scope({}, dao_factory.workspaces.find_all, {
          name = ws_name
        })
        if err then
          helpers.yield_error(err)
        end
        if #w == 0 then
          local err = fmt("Workspace %s does not exist", self.params.workspace)
          helpers.responses.send_HTTP_NOT_FOUND(err)
        end
      end

      if not rbac_operation_allowed(singletons.configuration,
        ctx.rbac, request_ws, ws_name) then
        local err_str = fmt(
          "%s is not allowed to create cross workspace permissions",
          ctx.rbac.user.name)
        helpers.responses.send_HTTP_FORBIDDEN(err_str)
      end

      local cache_key = dao_factory["rbac_roles"]:cache_key(self.rbac_role.id)
      singletons.cache:invalidate(cache_key)

      -- strip any whitespaces from both ends
      self.params.endpoint = utils.strip(self.params.endpoint)

      if self.params.endpoint ~= "*" then
        -- normalize endpoint: remove trailing /
        self.params.endpoint = ngx.re.gsub(self.params.endpoint, "/$", "")

        -- make sure the endpoint starts with /, unless it's '*'
        self.params.endpoint = ngx.re.gsub(self.params.endpoint, "^/?", "/")
      end

      crud.post(self.params, dao_factory.rbac_role_endpoints, post_process_actions)
    end,
  },

  ["/rbac/roles/:name_or_id/endpoints/:workspace/*"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
      self.params.role_id = self.rbac_role.id
      -- Note: /rbac/roles/:name_or_id/endpoints/:workspace// will be treated same as
      -- /rbac/roles/:name_or_id/endpoints/:workspace/
      -- this is the limitation of lapis implementation
      -- it's not possible to distinguish // from /
      -- since the self.params.splat will always be "/"
      if self.params.splat ~= "*" and self.params.splat ~= "/" then
        self.params.endpoint = "/" .. self.params.splat
      else
        self.params.endpoint = self.params.splat
      end
      self.params.splat = nil
    end,

    GET = function(self, dao_factory, helpers)
      crud.get(self.params, dao_factory.rbac_role_endpoints,
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

      crud.patch(self.params, dao_factory.rbac_role_endpoints, filter,
                 post_process_actions)
    end,

    DELETE = function(self, dao_factory, helpers)
      crud.delete(self.params, dao_factory.rbac_role_endpoints)
    end,
  },

  ["/rbac/roles/:name_or_id/endpoints/permissions"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_role_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local map = rbac.readable_endpoints_permissions({self.rbac_role})
      return helpers.responses.send_HTTP_OK(map)
    end,
  },

  ["/rbac/users/consumers"] = {
    POST = function(self, dao_factory)
      -- TODO: validate consumer and user here
      crud.post(self.params, dao_factory.consumers_rbac_users_map)
    end,
  },

  ["/rbac/users/:user_id/consumers/:consumer_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_rbac_user_consumer_map(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.consumers_rbac_users_map)
    end,
  },
}
