local crud  = require "kong.api.crud_helpers"
local utils = require "kong.tools.utils"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"
local endpoints = require "kong.api.endpoints"
local counters =  require "kong.workspaces.counters"


-- FT-258: To block some endpoints of being wrongly called from a
-- workspace namespace, we enforce that some workspace endpoints are
-- called either from the default workspace or from a different
-- workspace but having the same workspace passed as a parameter.
local function ensure_valid_workspace(self, helpers)
  local api_workspace = self.workspace
  local namespace_workspace = ngx.ctx.workspaces[1]

  -- call from default ws is ok.
  if namespace_workspace.name == workspaces.DEFAULT_WORKSPACE then
    return true
  end

  if api_workspace.id == namespace_workspace.id then
    -- if called under a different workspace namespace and the api has
    -- a workspace parameter on its own, ensure we're asking for the
    -- same
    return true
  end

  helpers.responses.send_HTTP_NOT_FOUND()
end


-- dev portal post-process: perform portal checks and create files
-- for the created/updated workspace if needed
local function portal_post_process(workspace, helpers)
  local dao = singletons.dao

  local workspace, err = crud.portal_crud.check_initialized(workspace, dao)
  if err then
    return helpers.yield_error(err)
  end

  return workspace
end


return {
  ["/workspaces"] = {
    before = function(self, _, helpers)
      -- FT-258
      if ngx.ctx.workspaces[1].name ~= workspaces.DEFAULT_WORKSPACE then
        helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    POST = function(self, _, helpers, parent)
      return parent(portal_post_process, helpers)
    end
  },

  ["/workspaces/:workspaces"] = {
    before = function(self, db, helpers)
      self.workspace = endpoints.select_entity(self, db, db["workspaces"].schema)
      if not self.workspace then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
      ensure_valid_workspace(self, helpers)
    end,

    PATCH = function(self, _, helpers, parent)
      -- disallow changing workspace name
      if self.params.name and self.params.name ~= self.workspace.name then
        return helpers.responses.send_HTTP_BAD_REQUEST("Cannot rename a workspace")
      end

      return parent(portal_post_process, helpers)
    end,

    -- XXX PORTAL: why wasn't there a post_process for portal on PUT?

    DELETE = function(self, db, helpers, parent)
      if self.workspace.name == workspaces.DEFAULT_WORKSPACE then
        return helpers.responses.send_HTTP_BAD_REQUEST("Cannot delete default workspace")
      end

      -- XXX compat_find_all will go away with workspaces remodel
      local results, err = workspaces.compat_find_all("workspace_entities", {
        workspace_id = self.workspace.id,
      })
      if err then
        return helpers.yield_error(err)
      end
      if #results > 0 then
        return helpers.responses.send_HTTP_BAD_REQUEST("Workspace is not empty")
      end

      return parent()
    end,
  },

  ["/workspaces/:workspaces/entities"] = {
    before = function(self, db, helpers)
      self.workspace = endpoints.select_entity(self, db, db["workspaces"].schema)
      if not self.workspace then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, db, helpers)
      ensure_valid_workspace(self, helpers)

      -- XXX compat_find_all will go away with workspaces remodel
      local entities, err = workspaces.compat_find_all("workspace_entities", {
        workspace_id = self.workspace.id,
      })
      if err then
        return helpers.yield_error(err)
      end

      return helpers.responses.send_HTTP_OK({
        data = entities,
        total = #entities,
      })
    end,

    POST = function(self, db, helpers)
      if not self.params.entities then
        return helpers.responses.send_HTTP_BAD_REQUEST("must provide >= entity")
      end

      -- XXX compat_find_all will go away with workspaces remodel
      local existing_entities, err = workspaces.compat_find_all("workspace_entities", {
        workspace_id = self.workspace.id,
      })
      if err then
        return helpers.yield_error(err)
      end

      local entity_ids = utils.split(self.params.entities, ",")

      for i = 1, #entity_ids do
        local e = entity_ids[i]

        if not utils.is_valid_uuid(e) then
          helpers.responses.send_HTTP_BAD_REQUEST("'" .. e .. "' is not a valid UUID")
        end

        -- duplication check
        for j = 1, #existing_entities do
          if e == existing_entities[j].entity_id then
            local err = "Entity '" .. e .. "' already associated " ..
                        "with workspace '" .. self.workspace.id .. "'"
            return helpers.responses.send_HTTP_CONFLICT(err)

          end
        end
      end

      -- yayyyy, no fuckup! now do the thing
      local res = {}
      for i = 1, #entity_ids do
        local entity_type, row, err = workspaces.resolve_entity_type(entity_ids[i])
        -- database error
        if entity_type == nil and err then
          return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
        end
        -- entity doesn't exist
        if entity_type == false or not row then
          return helpers.responses.send_HTTP_NOT_FOUND()
        end

        local err = workspaces.add_entity_relation(entity_type, row, self.workspace)
        if err then
          return helpers.yield_error(err)
        end
        table.insert(res, row)
      end


      return helpers.responses.send_HTTP_CREATED(res)
    end,

    DELETE = function(self, db, helpers)
      if not self.params.entities then
        return helpers.responses.send_HTTP_BAD_REQUEST("must provide >= entity")
      end

      local entity_ids = utils.split(self.params.entities, ",")

      for i = 1, #entity_ids do
        local e = entity_ids[i]

        -- XXX compat_find_all will go away with workspaces remodel
        local ws_e, err = workspaces.compat_find_all("workspace_entities", {
          workspace_id = self.workspace.id,
          entity_id = e,
        })
        if err then
          return helpers.yield_error(err)
        end
        if not ws_e[1] then
          return helpers.responses.send_HTTP_NOT_FOUND("entity " .. e .. " is not " ..
                                                       "in workspace " .. self.workspace.name)
        end

        for _, row in ipairs(ws_e) do
          local _, err = db.workspace_entities:delete({
            entity_id = row.entity_id,
            workspace_id = row.workspace_id,
            unique_field_name = row.unique_field_name,
          })
          if err then
            return helpers.yield_error(err)
          end
        end

        counters.inc_counter(db, self.workspace.id, ws_e[1].entity_type, { id = e }, -1)

        -- find out if the entity is still in any workspace
        -- XXX compat_find_all will go away with workspaces remodel
        local rows
        rows, err = workspaces.compat_find_all("workspace_entities", {
          entity_id = e, -- get the first result's entity_type;
                                           -- we can do that given the result in
                                           -- ws_e is for the same entity_id
          entity_type = ws_e[1].entity_type,
        })
        if err then
          return helpers.yield_error(err)
        end

        -- if entity_id is not part of any other workspaces, that means it's
        -- unreachable/dangling, so delete it
        if #rows == 0 then
          local entity_type = ws_e[1].entity_type

          -- which dao is that entity part of?
          local dao = db[entity_type] or singletons.db.daos[entity_type]

          local _, err = workspaces.run_with_ws_scope({}, dao.delete, dao, {
            id = e,
          }, {skip_rbac = true})
          if err then
            return helpers.yield_error(err)
          end
        end
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },

  ["/workspaces/:workspaces/entities/:entity_id"] = {
    before = function(self, db, helpers)
      self.workspace = endpoints.select_entity(self, db, db["workspaces"].schema)
      if not self.workspace then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, db, helpers)
      -- XXX compat_find_all will go away with workspaces remodel
      local e, err = workspaces.compat_find_all("workspace_entities", {
        workspace_id = self.workspace.id,
        entity_id = self.params.entity_id,
      })
      if err then
        return helpers.yield_error(err)
      end
      if not e[1] then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      e = e[1]
      e.unique_field_name = nil
      e.unique_field_value = nil

      return e and helpers.responses.send_HTTP_OK(e)
                or helpers.responses.send_HTTP_NOT_FOUND()
    end,

    DELETE = function(self, db, helpers)
      -- XXX compat_find_all will go away with workspaces remodel
      local e, err = workspaces.compat_find_all("workspace_entities", {
        workspace_id = self.workspace.id,
        entity_id = self.params.entity_id,
      })
      if err then
        return helpers.yield_error(err)
      end
      if not e[1] then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      for _, row in ipairs(e) do
        local _, err = db.workspace_entities:delete({
          entity_id = row.entity_id,
          workspace_id = row.workspace_id,
          unique_field_name = row.unique_field_name,
        })
        if err then
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },
  ["/workspaces/:workspaces/meta"] = {
    before = function(self, db, helpers)
      self.workspace = endpoints.select_entity(self, db, db["workspaces"].schema)
      if not self.workspace then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      ensure_valid_workspace(self, helpers)
    end,

    GET = function(self, _, helpers)
      local counts, err = counters.counts(self.workspace.id)
      if not counts then
        helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      return helpers.responses.send_HTTP_OK({counts = counts})
    end
  },

}
