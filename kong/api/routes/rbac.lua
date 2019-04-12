local utils     = require "kong.tools.utils"
local rbac      = require "kong.rbac"
local bit       = require "bit"
local cjson     = require "cjson"
local singletons = require "kong.singletons"
local tablex     = require "pl.tablex"
local api_helpers = require "kong.enterprise_edition.api_helpers"
local workspaces = require "kong.workspaces"


local band  = bit.band
local bxor  = bit.bxor
local fmt   = string.format


local rbac_users = kong.db.rbac_users
local rbac_roles = kong.db.rbac_roles
local endpoints   = require "kong.api.endpoints"

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
        return kong.response.exit(400, "Undefined RBAC action " ..
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


local function remove_default_roles(roles)
  return tablex.map(post_process_role,
    tablex.filter(roles,
      function(role)
        return not role.is_default
  end))
end


local function find_current_user(self, db, helpers)
  -- PUT creates if rbac_user doesn't exist, so exit early
  if kong.request.get_method() == "PUT" then
    return
  end

  local rbac_user, _, err_t = endpoints.select_entity(self, db, rbac_users.schema)
  if err_t then
    return endpoints.handle_error(err_t)
  end
  if not rbac_user then
    return kong.response.exit(404, { message = "No RBAC user by name or id " ..
                              self.params.rbac_users})
  end

  local admin, err = db.admins:select_by_rbac_user(rbac_user)

  if err then
    return kong.response.exit(500, err)
  end

  if admin then
    return kong.response.exit(404, { message = "Not Found" })
  end

  self.rbac_user = rbac_user
end

local function find_current_role(self, db, helpers)
  local rbac_role, _, err_t = endpoints.select_entity(self, db, rbac_roles.schema)
  if err_t then
    return endpoints.handle_error(err_t)
  end
  if not rbac_role then
    return kong.response.exit(404, { message = "Not found" })
  end

  self.rbac_role = rbac_role
  self.params.role = self.rbac_role
end


return {
  ["/rbac/users"] = {
    schema = rbac_users.schema,
    methods = {
      GET  =  function(self, db, helpers)
        local args = self.args.uri
        local opts = endpoints.extract_options(args, "rbac_users", "select")
        local size, err = endpoints.get_page_size(args)
        if err then
          return endpoints.handle_error(db.rbac_users.errors:invalid_size(err))
        end

        local data, _, err_t, offset = db.rbac_users:page(size, args.offset, opts)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        local next_page = offset and fmt("/%s?offset=%s",
          "rbac_users",
          endpoints.escape_uri(offset)) or ngx.null

        -- filter non-proxy rbac_users (consumers)
        local res = {}
        for _, v in ipairs(data) do
          -- XXX EE: Workaround for not showing admin rbac users
          local admin, err = db.admins:select_by_rbac_user(v)
          if err then
            return endpoints.handle_error(err_t)
          end

          if not admin then
            table.insert(res, v)
          end
        end

        return kong.response.exit(200, {
          data   = res,
          offset = offset,
          next   = next_page,
        })
      end,

      -- post_process_user should be called after GET , but no
      -- post_processing for GETS in endpoints framework
      POST = function(self, db, helpers, post_process)
        return endpoints.post_collection_endpoint(rbac_users.schema)(self, db, helpers)
      end
    }
  },

  ["/rbac/users/:rbac_users"] = {
    schema = rbac_users.schema,
    methods = {
      before = function(self, db, helpers)
        find_current_user(self, db, helpers)
      end,

      GET = function(self, db, helpers)
          return kong.response.exit(200, self.rbac_user)
        end,

      PATCH = endpoints.patch_entity_endpoint(rbac_users.schema),
      DELETE  = function(self, db, helpers)
        -- endpoints.delete_entity_endpoint(rbac_users.schema)(self, db, helpers)

        db.rbac_users:delete({id = self.rbac_user.id })

        local default_role = db.rbac_roles:select_by_name(self.rbac_user.name)
        if default_role then
          local _, err = rbac.remove_user_from_default_role(self.rbac_user,
            default_role)
          if err then
            helpers.yield_error(err)
          end
        end

        return kong.response.exit(204)
      end
    }
  },
  ["/rbac/users/:rbac_users/permissions"] = {
    schema = rbac_users.schema,
    methods = {
      GET = function(self, db, helpers)
        find_current_user(self, db, helpers)
        local roles, err = rbac.get_user_roles(db, self.rbac_user)
        if err then
          ngx.log(ngx.ERR, "[rbac] ", err)
          return kong.response.exit(500)
        end

        local map = {}
        local entities_perms = rbac.readable_entities_permissions(roles)
        local endpoints_perms = rbac.readable_endpoints_permissions(roles)

        map.entities = entities_perms
        map.endpoints = endpoints_perms

        return kong.response.exit(200, map)
      end
    }
  },
  ["/rbac/users/:rbac_users/roles"] = {
    schema = rbac_users.schema,
    methods = {
      GET = function(self, db, helpers)
        find_current_user(self, db, helpers)
        local rbac_roles = rbac.get_user_roles(db, self.rbac_user)
        rbac_roles = remove_default_roles(rbac_roles)

        setmetatable(rbac_roles, cjson.empty_array_mt)
        return kong.response.exit(200, {
          user = self.rbac_user,
          roles = rbac_roles
        })
      end,
      POST = function(self, db, helpers)
        find_current_user(self, db, helpers)
        -- we have the user, now verify our roles
        if not self.params.roles then
          return kong.response.exit(400, "must provide >= 1 role")
        end

        local roles, err = rbac.objects_from_names(db, self.params.roles, "role")
        if err then
          if err:find("not found with name", nil, true) then
            return kong.response.exit(400, {message = err})
          else
            return helpers.yield_error(err)
          end
        end

        -- we've now validated that all our roles exist, and this user exists,
        -- so time to create the assignment
        for i = 1, #roles do
          local _, _, err_t = db.rbac_user_roles:insert({
            user = self.rbac_user,
            role = roles[i]
          })

          if err_t then
            return endpoints.handle_error(err_t) -- XXX EE: 400 vs
                                                 -- 409. primary key
                                                 -- validation failed
          end
        end

        -- invalidate rbac user so we don't fetch the old roles
        local cache_key = db["rbac_user_roles"]:cache_key(self.rbac_user.id)
        singletons.cache:invalidate(cache_key)

        -- re-fetch the users roles so we show all the role objects, not just our
        -- newly assigned mappings

        -- roles, err = db.rbac_users:get_roles(db, self.rbac_user)
        roles, err = rbac.get_user_roles(db, self.rbac_user)

        if err then
          return helpers.yield_error(err)
        end

        roles = remove_default_roles(roles)

        -- show the user and all of the roles they are in
        return kong.response.exit(201, {
          user  = self.rbac_user,
          roles = roles,
        })
      end,

      DELETE = function(self, db, helpers)
        if not self.params.roles then
          return kong.response.exit(400, {message = "must provide >= 1 role"})
        end
        find_current_user(self, db, helpers)

        local roles, err = rbac.objects_from_names(db, self.params.roles, "role")
        if err then
          if err:find("not found with name", nil, true) then
            return kong.response.exit(400, {message = err})

          else
            return helpers.yield_error(err)
          end
        end

        for i = 1, #roles do
          db.rbac_user_roles:delete({
            user = { id = self.rbac_user.id } ,
            role = { id = roles[i].id },
          })
        end

        local cache_key = db.rbac_user_roles:cache_key(self.rbac_user.id)
        singletons.cache:invalidate(cache_key)

        return kong.response.exit(204)
      end
    },
  },
  ["/rbac/roles"] = {
    schema = rbac_roles.schema,
    methods = {
      GET  = function(self, db, helpers, parent)
        local args = self.args.uri
        local opts = endpoints.extract_options(args, "rbac_roles", "select")
        local size, err = endpoints.get_page_size(args)
        if err then
          return endpoints.handle_error(db.rbac_roles.errors:invalid_size(err))
        end

        local data, _, err_t, offset = db.rbac_roles:page(size, args.offset, opts)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        data = remove_default_roles(data)

        local next_page = offset and fmt("/%s?offset=%s",
          "rbac_roles",
          endpoints.escape_uri(offset)) or ngx.null


        return kong.response.exit(200, {
          data   = data,
          offset = offset,
          next   = next_page,
        })
      end,
      POST = endpoints.post_collection_endpoint(rbac_roles.schema),
    }
  },
  ["/rbac/roles/:rbac_roles/permissions"] = {
    schema = rbac_roles.schema,
    methods = {
      GET = function(self, db, helpers)
        find_current_role(self, db, helpers)

        local map = {}
        local entities_perms = rbac.readable_entities_permissions({self.rbac_role})
        local endpoints_perms = rbac.readable_endpoints_permissions({self.rbac_role})

        map.entities = entities_perms
        map.endpoints = endpoints_perms

        return kong.response.exit(200, map)
      end
    }
  },

  ["/rbac/roles/:rbac_roles"] = {
    schema = rbac_roles.schema ,
    methods = {
      GET  = endpoints.get_entity_endpoint(rbac_roles.schema),
      PUT     = endpoints.put_entity_endpoint(rbac_roles.schema),
      PATCH   = endpoints.patch_entity_endpoint(rbac_roles.schema),

      DELETE = function(self, db, helpers)
        local rbac_role, _, err_t = endpoints.select_entity(self, db, rbac_roles.schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        self.rbac_role = rbac_role

        db.rbac_roles:delete({ id = rbac_role.id })
        return kong.response.exit(204)
      end,
    },
  },

  ["/rbac/roles/:rbac_roles/entities"] = {
    schema = rbac_roles.schema,
    methods = {
    before = function(self, db, helpers)
      find_current_role(self, db, helpers)
    end,
    GET = function(self, db, helpers)
      -- XXX: EE. do proper pagination.  Investigate if we can page through it
      local entities = rbac.get_role_entities(db, self.rbac_role)

      entities = tablex.map(post_process_actions, entities)

      return kong.response.exit(200, {
        data = entities
      })
    end,

    POST = function(self, db, helpers)
      action_bitfield(self)

      if not self.params.entity_id then
        return kong.response.exit(400, "Missing required parameter: 'entity_id'")
      end

      local entity_type = "wildcard"
      if self.params.entity_id ~= "*" then
        local _, err
        entity_type, _, err = api_helpers.resolve_entity_type(singletons.db,
                                                              singletons.dao,
                                                              self.params.entity_id)
        -- database error
        if entity_type == nil then
          return kong.response.exit(500, err)
        end
        -- entity doesn't exist
        if entity_type == false then
          return kong.response.exit(400, err)
        end
      end

      self.params.entity_type = entity_type

      local role_entity, _, err_t = db.rbac_role_entities:insert({
        entity_id = self.params.entity_id,
        role = self.rbac_role,
        entity_type = entity_type,
        actions = self.params.actions,
        negative = self.params.negative,
        comment = self.params.comment,
      })
      if err_t then
        return error(err_t)
      end

      return kong.response.exit(201, post_process_actions(role_entity))
    end,
    }
  },

  ["/rbac/roles/:rbac_roles/entities/:entity_id"] = {
    schema = rbac_roles.schema,
    methods = {
      before = function(self, db, helpers)
        local rbac_role, _, err_t = endpoints.select_entity(self, db, rbac_roles.schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not rbac_role then
          return kong.response.exit(404, { message = "Not found" })
        end
        self.rbac_role = rbac_role
        self.rbac_role_id = rbac_role.id

        if self.params.entity_id ~= "*" and not utils.is_valid_uuid(self.params.entity_id) then
          return kong.response.exit(400,
            self.params.entity_id .. " is not a valid uuid")
        end
        self.entity_id = self.params.entity_id
      end,

      GET = function(self, db, helpers)
        local entity, _, err_t = db.rbac_role_entities:select({
          entity_id = self.entity_id,
          role = { id = self.rbac_role_id },
        })
        if err_t then
          return endpoints.handle_error(err_t)
        end

        if entity then
          return kong.response.exit(200, post_process_actions(entity))
        end

        return kong.response.exit(404, { message = "Not Found" })
      end,
      DELETE = function(self, db, helpers)
        local _, _, err_t = db.rbac_role_entities:delete({
          entity_id = self.entity_id,
          role = { id = self.rbac_role_id },
        })
        if err_t then
          return endpoints.handle_error(err_t)
        end

        return kong.response.exit(204)
      end,

      PATCH = function(self, db, helpers)
        if self.params.actions then
          action_bitfield(self)
        end

        self.params.entity_id = nil
        self.params.role_id = nil
        self.params.rbac_role_id = nil
        self.params.rbac_roles = nil


        local entity = db.rbac_role_entities:update({
          entity_id = self.entity_id,
          role = { id = self.rbac_role_id }
          }, self.params)
        if not entity then
          kong.response.exit(404)
        end

        return kong.response.exit(200, post_process_actions(entity))
      end,
    },

  --   GET = function(self, dao_factory, helpers)
  --     crud.get(self.params, dao_factory.rbac_role_entities,
  --              post_process_actions)
  --   end,

  --   PATCH = function(self, dao_factory, helpers)
  --     if self.params.actions then
  --       action_bitfield(self)
  --     end

  --     local filter = {
  --       role_id = self.params.role_id,
  --       entity_id = self.params.entity_id,
  --     }

  --     self.params.role_id = nil
  --     self.params.entity_id = nil

  --     crud.patch(self.params, dao_factory.rbac_role_entities, filter,
  --                post_process_actions)
  --   end,

  --   DELETE = function(self, dao_factory, helpers)
  --     crud.delete(self.params, dao_factory.rbac_role_entities)
      --   end,
  },

  ["/rbac/roles/:rbac_roles/entities/permissions"] = {
    schema = rbac_roles.schema,
    methods = {
      GET = function(self, db, helpers)
        find_current_role(self, db, helpers)
        local map = rbac.readable_entities_permissions({self.rbac_role})
        return kong.response.exit(200, map)
      end,
    }
  },

  ["/rbac/roles/:rbac_roles/endpoints"] = {
    schema = rbac_roles.schema,
    methods = {
      before = function(self, db, helpers)
        find_current_role(self, db, helpers)
      end,

      GET = function(self, db, helpers)
        local endpoints = rbac.get_role_endpoints(db, self.rbac_role)

        tablex.map(post_process_actions, endpoints) -- post_process_actions
        return kong.response.exit(200, { -- XXX EE. Should we keep old
                                         -- structure? or should we
                                         -- just return endoints and
                                         -- that's it? also, pagination?
          data = endpoints
        })
      end,

      POST = function(self, dao_factory, helpers)
        action_bitfield(self)
        if not self.params.endpoint then
          kong.response.exit(400, {message = "'endpoint' is a required field"})
        end

        local ctx = ngx.ctx
        local request_ws = ctx.workspaces[1]

        -- if the `workspace` parameter wasn't passed, fallback to the current
        -- request's workspace
        self.params.workspace = self.params.workspace or request_ws.name

        local ws_name = self.params.workspace

        if ws_name ~= "*" then
          local w, err = workspaces.run_with_ws_scope({}, singletons.dao.workspaces.find_all, singletons.dao.workspaces, {
            name = ws_name
          })
          if err then
            helpers.yield_error(err)
          end
          if #w == 0 then
            local err = fmt("Workspace %s does not exist", self.params.workspace)
            kong.response.exit(404, { message = err})
          end
        end

        if not rbac_operation_allowed(singletons.configuration,
          ctx.rbac, request_ws, ws_name) then
          local err_str = fmt(
            "%s is not allowed to create cross workspace permissions",
            ctx.rbac.user.name)
          kong.response.exit(403, {message = err_str})
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

        self.params.rbac_roles = nil
        local row, err = singletons.db.rbac_role_endpoints:insert(self.params)
        if err then
          return kong.response.exit(409, {message = err})
        end

        return kong.response.exit(201, post_process_actions(row))
      end,
    },
  },
  ["/rbac/roles/:rbac_roles/endpoints/:workspace/*"] = {
    schema = kong.db.rbac_role_endpoints.schema,
    methods = {
      before = function(self, db, helpers)
        local rbac_role, _, err_t = endpoints.select_entity(self, db, rbac_roles.schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not rbac_role then
          return kong.response.exit(404, { message = "Not found" })
        end
        self.rbac_role = rbac_role
        self.params.role_id = self.rbac_role.id
        self.params.role =  self.rbac_role

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

      GET = function(self, db, helpers)
        local endpoints = rbac.get_role_endpoints(db, self.rbac_role)
        for _, e in ipairs(endpoints) do
          if e.endpoint == self.params.endpoint  then
            kong.response.exit(200, post_process_actions(e))
          end
        end
        kong.response.exit(404)
      end,

      PATCH = function(self, db, helpers)
        if self.params.actions then
          action_bitfield(self)
        end

        local filter = {
          role = { id = self.params.role.id, },
          workspace = self.params.workspace,
          endpoint = self.params.endpoint,
        }

        self.params.role_id = nil
        self.params.workspace = nil
        self.params.endpoint = nil
        self.params.rbac_roles = nil

        local endpoint = db.rbac_role_endpoints:update(filter, self.params)
        if not endpoint then
          return kong.response.exit(404)
        end

        return kong.response.exit(200, post_process_actions(endpoint))
      end,

      DELETE = function(self, db, helpers)
        local filter = {
          role = { id = self.params.role_id, },
          workspace = self.params.workspace,
          endpoint = self.params.endpoint,
        }
        db.rbac_role_endpoints:delete(filter)
        return kong.response.exit(204)
      end,
    }
  },

  ["/rbac/roles/:rbac_roles/endpoints/permissions"] = {
    schema = rbac_roles.schema,
    methods = {
      before = function(self, db, helpers)
        find_current_role(self, db, helpers)
      end,

      GET = function(self, dao_factory, helpers)
        local map = rbac.readable_endpoints_permissions({self.rbac_role})
        return kong.response.exit(200, map)
      end,
    }
  },

}
