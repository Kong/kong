-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils     = require "kong.tools.utils"
local rbac      = require "kong.rbac"
local bit       = require "bit"
local clone      = require "table.clone"
local cjson     = require "cjson"
local tablex     = require "pl.tablex"
local constants = require "kong.constants"
local workspaces = require "kong.workspaces"


local kong       = kong
local band       = bit.band
local bxor       = bit.bxor
local fmt        = string.format
local escape_uri = ngx.escape_uri
local unescape_uri = ngx.unescape_uri
local null       = ngx.null

local rbac_users          = kong.db.rbac_users
local rbac_roles          = kong.db.rbac_roles
local rbac_role_entities  = kong.db.rbac_role_entities
local rbac_role_endpoints = kong.db.rbac_role_endpoints
local endpoints           = require "kong.api.endpoints"

local PORTAL_PREFIX = constants.PORTAL_PREFIX
local PORTAL_PREFIX_LEN = #PORTAL_PREFIX


local function rbac_operation_allowed(kong_conf, rbac_ctx, current_ws_id, dest_ws)
  if kong_conf.rbac == "off" then
    return true
  end

  if dest_ws and current_ws_id == dest_ws.id then
    return true
  end

  -- dest is different from current
  local dest_ws_name
  if dest_ws then
    dest_ws_name = dest_ws.name
  end
  if rbac.user_can_manage_endpoints_from(rbac_ctx, dest_ws_name) then
    return true
  end

  return false
end


local function action_bitfield(self)
  local bitfield = 0x0
  local action_names = {}
  if type(self.params.actions) == "string" then
    action_names = utils.split(self.params.actions, ",")
  end

  if type(self.params.actions) == "table" then
    action_names = self.params.actions
  end
  for i = 1, #action_names do
    local action = action_names[i]

    -- keyword all sets everything
    if action == "*" then
      for k in pairs(rbac.actions_bitfields) do
        bitfield = bxor(bitfield, rbac.actions_bitfields[k])
      end

      break
    end

    if not rbac.actions_bitfields[action] then
      return kong.response.exit(400, { message = "Undefined RBAC action " ..
          action_names[i] })
    end

    bitfield = bxor(bitfield, rbac.actions_bitfields[action])
  end

  self.params.actions = bitfield
end


local function post_process_actions(row)
  -- shallow copy to a new row to prevent modifying cache accidentally
  local new_row = clone(row)
  local actions_t = setmetatable({}, cjson.empty_array_mt)
  local actions_t_idx = 0

  for k, n in pairs(rbac.actions_bitfields) do
    if band(n, new_row.actions) == n then
      actions_t_idx = actions_t_idx + 1
      actions_t[actions_t_idx] = k
    end
  end


  new_row.actions = actions_t
  return new_row
end


local function post_process_role(role)
  -- don't expose column that is for internal use only
  role.is_default = nil
  return role
end


local function post_process_filter_roles(role)
  -- remove default roles
  if role.is_default then
    return
  end

  -- remove portal roles
  if string.sub(role.name, 1, PORTAL_PREFIX_LEN) == PORTAL_PREFIX then
    return
  end

  return post_process_role(role)
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
        local opts = endpoints.extract_options(args, rbac_users.schema, "select")
        local size, err = endpoints.get_page_size(args)
        if err then
          return endpoints.handle_error(db.rbac_users.errors:invalid_size(err))
        end

        local data, _, err_t, offset = db.rbac_users:page(size, args.offset, opts)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        local next_page = offset and fmt("/rbac/users?offset=%s",
          escape_uri(offset)) or ngx.null

        -- filter non-proxy rbac_users (consumers)
        local res = {}
        setmetatable(res, cjson.empty_array_mt)

        for _, v in ipairs(data) do
          -- XXX EE: Workaround for not showing admin rbac users
          local admin, err = db.admins:select_by_rbac_user(v)
          if err then
            return endpoints.handle_error(err_t)
          end

          -- filter developer rbac users
          local prefix = string.sub(v.name, 1, PORTAL_PREFIX_LEN)
          local developer = prefix == PORTAL_PREFIX

          if not admin and not developer then
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
          local _, err = rbac.remove_default_role_if_empty(default_role, ngx.ctx.workspace)
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
        local roles, err = rbac.get_user_roles(db, self.rbac_user, ngx.ctx.workspace)
        if err then
          ngx.log(ngx.ERR, "[rbac] ", err)
          return kong.response.exit(500, { message = "An unexpected error occurred" })
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
        local rbac_roles = rbac.get_user_roles(db, self.rbac_user, ngx.ctx.workspace)
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
          return kong.response.exit(400, { message = "must provide >= 1 role" })
        end

        local roles, err = rbac.objects_from_names(db, self.params.roles, "role")
        if err then
          if err:find("not found with name", nil, true) then
            return kong.response.exit(400, { message = err })
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
            return endpoints.handle_error(err_t)
          end
        end

        -- invalidate rbac user so we don't fetch the old roles
        local cache_key = db["rbac_user_roles"]:cache_key(self.rbac_user.id)
        kong.cache:invalidate(cache_key)

        -- re-fetch the users roles so we show all the role objects, not just our
        -- newly assigned mappings

        -- roles, err = db.rbac_users:get_roles(db, self.rbac_user)
        roles, err = rbac.get_user_roles(db, self.rbac_user, ngx.ctx.workspace)

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
          return kong.response.exit(400, { message = "must provide >= 1 role" })
        end
        find_current_user(self, db, helpers)

        local roles, err = rbac.objects_from_names(db, self.params.roles, "role")
        if err then
          if err:find("not found with name", nil, true) then
            return kong.response.exit(400, { message = err })

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
        kong.cache:invalidate(cache_key)

        return kong.response.exit(204)
      end
    },
  },
  ["/rbac/roles"] = {
    schema = rbac_roles.schema,
    methods = {
      GET  = function(self, db, helpers, parent)
      local next_url = {}
      local next_page = null
      local args = self.args.uri

      self.args.uri.filter = post_process_filter_roles
      local data, _, err_t, offset =
        endpoints.page_collection(self, db, rbac_roles.schema, "filter_page")

      if err_t then
        return endpoints.handle_error(err_t)
      end

      if offset then
        table.insert(next_url, fmt("offset=%s", escape_uri(offset)))

        if args.tags then
          table.insert(next_url,
            "tags=" .. escape_uri(type(args.tags) == "table" and args.tags[1] or args.tags))
        end

        next_page = "/rbac/roles?" .. table.concat(next_url, "&")
      else
        offset = null
      end

      setmetatable(data, cjson.empty_array_mt)

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

        if rbac_role then
          db.rbac_roles:delete({ id = rbac_role.id })
        end

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
      return endpoints.get_collection_endpoint(rbac_role_entities.schema,
                                               rbac_roles.schema,
                                               "role")
                                              (self, db, helpers,
                                               post_process_actions)
    end,

    POST = function(self, db, helpers)
      action_bitfield(self)

      if not self.params.entity_id then
        return kong.response.exit(400, {
          message = "Missing required parameter: 'entity_id'"
        })
      end

      local entity_type = self.params.entity_type
      if self.params.entity_id == "*" then
        entity_type = "wildcard"
      end

      if not entity_type then
        return kong.response.exit(400, {
          message = "Missing required parameter: 'entity_type'"
        })
      end

      if entity_type ~= "wildcard" then
        if not db[entity_type] or not db[entity_type]:select({ id = self.params.entity_id }) then
          return kong.response.exit(400, {
            message = "There is no entity of type '" .. entity_type .. "' with given entity_id"
          })
        end
      end

      local role_entity, _, err_t = db.rbac_role_entities:insert({
        entity_id = self.params.entity_id,
        role = self.rbac_role,
        entity_type = entity_type,
        actions = self.params.actions,
        negative = self.params.negative,
        comment = self.params.comment,
      })
      if err_t then
        return endpoints.handle_error(err_t)
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
          return kong.response.exit(400, {
            message = self.params.entity_id .. " is not a valid uuid"
          })
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
          kong.response.exit(404, { message = "Not found" })
        end

        return kong.response.exit(200, post_process_actions(entity))
      end,
    },
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
       return endpoints.get_collection_endpoint(rbac_role_endpoints.schema,
                                                rbac_roles.schema,
                                                "role")
                                                (self, db, helpers,
                                                 post_process_actions)
      end,

      POST = function(self, db, helpers)
        action_bitfield(self)
        if not self.params.endpoint then
          kong.response.exit(400, {
            message = "'endpoint' is a required field"
          })
        end

        local request_ws_id = workspaces.get_workspace_id()

        local param_ws
        if self.params.workspace ~= "*" then
          local w, err
          if self.params.workspace then
            w, err = kong.db.workspaces:select_by_name(self.params.workspace)
            if err then
              helpers.yield_error(err)
            end

            if not w then
              local err = fmt("Workspace %s does not exist", self.params.workspace)
              kong.response.exit(404, { message = err})
            end
          else
            w, err = kong.db.workspaces:select({ id = request_ws_id })
            if err then
              helpers.yield_error(err)
            end

            self.params.workspace = w.name
          end

          param_ws = w
        end

        if not rbac_operation_allowed(kong.configuration,
          ngx.ctx.rbac, request_ws_id, param_ws) then
          local err_str = fmt(
            "%s is not allowed to create cross workspace permissions",
            ngx.ctx.rbac.user.name)
          kong.response.exit(403, { message = err_str })
        end

        local cache_key = db.rbac_roles:cache_key(self.rbac_role.id)
        kong.cache:invalidate(cache_key)

        -- strip any whitespaces from both ends
        self.params.endpoint = utils.strip(self.params.endpoint)

        if self.params.endpoint ~= "*" then
          -- normalize endpoint: remove trailing /
          self.params.endpoint = ngx.re.gsub(self.params.endpoint, "/$", "")

          -- make sure the endpoint starts with /, unless it's '*'
          self.params.endpoint = ngx.re.gsub(self.params.endpoint, "^/?", "/")
        end

        self.params.rbac_roles = nil
        local row, _, err_t = kong.db.rbac_role_endpoints:insert(self.params)
        if err_t then
          return endpoints.handle_error(err_t)
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
        local workspace = unescape_uri(self.params.workspace)
        for _, e in ipairs(endpoints) do
          if e.endpoint == self.params.endpoint and e.workspace == workspace then
            kong.response.exit(200, post_process_actions(e))
          end
        end
        kong.response.exit(404, { message = "Not found" })
      end,

      PATCH = function(self, db, helpers)
        if self.params.actions then
          action_bitfield(self)
        end

        local filter = {
          role = { id = self.params.role.id, },
          workspace = unescape_uri(self.params.workspace),
          endpoint = self.params.endpoint,
        }

        self.params.role_id = nil
        self.params.workspace = nil
        self.params.endpoint = nil
        self.params.rbac_roles = nil

        local endpoint = db.rbac_role_endpoints:update(filter, self.params)
        if not endpoint then
          return kong.response.exit(404, { message = "Not found" })
        end

        return kong.response.exit(200, post_process_actions(endpoint))
      end,

      DELETE = function(self, db, helpers)
        local filter = {
          role = { id = self.params.role_id, },
          workspace = unescape_uri(self.params.workspace),
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

      GET = function(self, db, helpers)
        local map = rbac.readable_endpoints_permissions({self.rbac_role})
        return kong.response.exit(200, map)
      end,
    }
  },

}
