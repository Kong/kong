local utils = require "kong.tools.utils"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"
local endpoints = require "kong.api.endpoints"
local counters =  require "kong.workspaces.counters"
local portal_crud = require "kong.portal.crud_helpers"


local kong = kong


-- FT-258: To block some endpoints of being wrongly called from a
-- workspace namespace, we enforce that some workspace endpoints are
-- called either from the default workspace or from a different
-- workspace but having the same workspace passed as a parameter.
local function ensure_valid_workspace(self)
  local api_workspace = self.workspace
  local namespace_workspace = ngx.ctx.workspaces[1]

  -- call from default ws is ok.
  if namespace_workspace.name == workspaces.DEFAULT_WORKSPACE then
    return true
  end

  if api_workspace and api_workspace.id == namespace_workspace.id then
    -- if called under a different workspace namespace and the api has
    -- a workspace parameter on its own, ensure we're asking for the
    -- same
    return true
  end

  return kong.response.exit(404, {message = "Not found"})
end


-- dev portal post-process: perform portal checks and create files
-- for the created/updated workspace if needed
local function portal_post_process(workspace)
  local workspace, err = portal_crud.check_initialized(workspace, kong.db)
  if err then
    return kong.response.exit(500, {message = err})
  end

  return workspace
end


return {
  ["/workspaces"] = {
    before = function(self)
      -- FT-258
      if ngx.ctx.workspaces[1].name ~= workspaces.DEFAULT_WORKSPACE then
        return kong.response.exit(404, {message = "Not found"})
      end
    end,

    POST = function(self, _, _, parent)
      return parent(portal_post_process)
    end
  },

  ["/workspaces/:workspaces"] = {
    before = function(self, db)
      self.workspace = endpoints.select_entity(self, db, db["workspaces"].schema)
      ensure_valid_workspace(self)
    end,

    PATCH = function(self, _, _, parent)
      if not self.workspace then
        return kong.response.exit(404, {message = "Not found"})
      end

      -- disallow changing workspace name
      if self.params.name and self.params.name ~= self.workspace.name then
        return kong.response.exit(400, {message = "Cannot rename a workspace"})
      end

      return parent(portal_post_process)
    end,

    PUT = function(self, _, _, parent)
      -- if updating, disallow changing workspace name
      if self.workspace and self.params.name and self.params.name ~= self.workspace.name then
        return kong.response.exit(400, {message = "Cannot rename a workspace"})
      end

      return parent(portal_post_process)
    end,

    -- XXX PORTAL: why wasn't there a post_process for portal on PUT?

    DELETE = function(self, db, _, parent)
      if not self.workspace then
        return kong.response.exit(404, {message = "Not found"})
      end

      if self.workspace.name == workspaces.DEFAULT_WORKSPACE then
        return kong.response.exit(400, {message = "Cannot delete default workspace"})
      end

      local results, err = db.workspace_entities:select_all({
        workspace_id = self.workspace.id,
      })
      if err then
        return kong.response.exit(500, {err})
      end
      if #results > 0 then
        return kong.response.exit(400, {message = "Workspace is not empty"})
      end

      return parent()
    end,
  },

  ["/workspaces/:workspaces/entities"] = {
    before = function(self, db)
      self.workspace = endpoints.select_entity(self, db, db["workspaces"].schema)
      if not self.workspace then
        return kong.response.exit(404, {message = "Not found"})
      end
    end,

    GET = function(self, db)
      ensure_valid_workspace(self)

      local entities, err = db.workspace_entities:select_all({
        workspace_id = self.workspace.id,
      })
      if err then
        return kong.response.exit(500, {message = err})
      end

      return kong.response.exit(200, {
        data = entities,
        total = #entities,
      })
    end,

    POST = function(self, db)
      if not self.params.entities then
        return kong.response.exit(400, {message = "must provide >= entity"})
      end

      local existing_entities, err = db.workspace_entities:select_all({
        workspace_id = self.workspace.id,
      })
      if err then
        return kong.response.exit(500, {message = err})
      end

      local entity_ids = utils.split(self.params.entities, ",")

      for i = 1, #entity_ids do
        local e = entity_ids[i]

        if not utils.is_valid_uuid(e) then
          return kong.response.exit(400, {message = "'" .. e .. "' is not a valid UUID"})
        end

        -- duplication check
        for j = 1, #existing_entities do
          if e == existing_entities[j].entity_id then
            local err = "Entity '" .. e .. "' already associated " ..
                        "with workspace '" .. self.workspace.id .. "'"
            return kong.response.exit(409, {message = err})

          end
        end
      end

      -- yayyyy, no fuckup! now do the thing
      local res = {}
      for i = 1, #entity_ids do
        local entity_type, row, err = workspaces.resolve_entity_type(entity_ids[i])
        -- database error
        if entity_type == nil and err then
          return kong.response.exit(500, {message = err})
        end
        -- entity doesn't exist
        if entity_type == false or not row then
          return kong.response.exit(404, {message = "Not found"})
        end

        local err = workspaces.add_entity_relation(entity_type, row, self.workspace)
        if err then
          return kong.response.exit(500, {message = err})
        end
        table.insert(res, row)
      end


      return kong.response.exit(201, res)
    end,

    DELETE = function(self, db)
      if not self.params.entities then
        return kong.response.exit(400, {message = "must provide >= entity"})
      end

      local entity_ids = utils.split(self.params.entities, ",")

      for i = 1, #entity_ids do
        local e = entity_ids[i]

        local ws_e, err = db.workspace_entities:select_all({
          workspace_id = self.workspace.id,
          entity_id = e,
        })
        if err then
          return kong.response.exit(500, {message = err})
        end
        if not ws_e[1] then
          return kong.response.exit(404, {message = "entity " .. e .. " is not " ..
                                                    "in workspace " .. self.workspace.name})
        end

        for _, row in ipairs(ws_e) do
          local _, err = db.workspace_entities:delete({
            entity_id = row.entity_id,
            workspace_id = row.workspace_id,
            unique_field_name = row.unique_field_name,
          })
          if err then
            return kong.response.exit(500, {message = err})
          end
        end

        counters.inc_counter(db, self.workspace.id, ws_e[1].entity_type, { id = e }, -1)

        -- find out if the entity is still in any workspace
        local rows
        rows, err = db.workspace_entities:select_all({
          entity_id = e, -- get the first result's entity_type;
                                           -- we can do that given the result in
                                           -- ws_e is for the same entity_id
          entity_type = ws_e[1].entity_type,
        })
        if err then
          return kong.response.exit(500, {message = err})
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
            return kong.response.exit(500, {message = err})
          end
        end
      end

      return kong.response.exit(204)
    end,
  },

  ["/workspaces/:workspaces/entities/:entity_id"] = {
    before = function(self, db)
      self.workspace = endpoints.select_entity(self, db, db["workspaces"].schema)
      if not self.workspace then
        return kong.response.exit(404, {message = "Not found"})
      end
    end,

    GET = function(self, db)
      local e, err = db.workspace_entities:select_all({
        workspace_id = self.workspace.id,
        entity_id = self.params.entity_id,
      })
      if err then
        return kong.response.exit(500, {message = err})
      end
      if not e[1] then
        return kong.response.exit(404, {message = "Not found"})
      end

      e = e[1]
      e.unique_field_name = nil
      e.unique_field_value = nil

      return e and kong.response.exit(200, e)
                or kong.response.exit(404, {message = "Not found"})
    end,

    DELETE = function(self, db)
      local e, err = db.workspace_entities:select_all({
        workspace_id = self.workspace.id,
        entity_id = self.params.entity_id,
      })
      if err then
        return kong.response.exit(500, {message = err})
      end
      if not e[1] then
        return kong.response.exit(404, {message = "Not found"})
      end

      for _, row in ipairs(e) do
        local _, err = db.workspace_entities:delete({
          entity_id = row.entity_id,
          workspace_id = row.workspace_id,
          unique_field_name = row.unique_field_name,
        })
        if err then
          return kong.response.exit(500, {message = err})
        end
      end

      return kong.response.exit(204)
    end,
  },
  ["/workspaces/:workspaces/meta"] = {
    before = function(self, db)
      self.workspace = endpoints.select_entity(self, db, db["workspaces"].schema)
      if not self.workspace then
        return kong.response.exit(404, {message = "Not found"})
      end

      ensure_valid_workspace(self)
    end,

    GET = function(self)
      local counts, err = counters.counts(self.workspace.id)
      if not counts then
        return kong.response.exit(500, {message = err})
      end

      return kong.response.exit(200, {counts = counts})
    end
  },

}
