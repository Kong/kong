local cjson = require "cjson"
local crud  = require "kong.api.crud_helpers"
local utils = require "kong.tools.utils"
local rbac  = require "kong.rbac"
local workspaces = require "kong.workspaces"


return {
  ["/workspaces/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.workspaces)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.workspaces)
    end,

    POST = function(self, dao_factory, helpers)
      crud.post(self.params, dao_factory.workspaces, function(workspace)
        local workspace, err = crud.portal_crud.check_initialized(workspace, dao_factory)
        if not workspace then
          return helpers.yield_error(err)
        end

        return workspace
      end)
    end,
  },

  ["/workspaces/:workspace_name_or_id"] = {
    before = function(self, dao_factory, helpers)
      self.params.workspace_name_or_id = ngx.unescape_uri(self.params.workspace_name_or_id)
      crud.find_workspace_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.workspace)
    end,

    PATCH = function(self, dao_factory, helpers)
      crud.patch(self.params, dao_factory.workspaces, self.workspace, function(workspace)
        local workspace, err = crud.portal_crud.check_initialized(workspace, dao_factory)
        if not workspace then
          return helpers.yield_error(err)
        end

        return workspace
      end)
    end,

    DELETE = function(self, dao_factory, helpers)
      if self.workspace.name == workspaces.DEFAULT_WORKSPACE then
        return helpers.responses.send_HTTP_BAD_REQUEST("Cannot delete default workspace")
      end

      local results, err = dao_factory.workspace_entities:find_all({
        workspace_id = self.workspace.id,
      })
      if err then
        return helpers.yield_error(err)
      end

      if #results > 0 then
        return helpers.responses.send_HTTP_BAD_REQUEST("Workspace is not empty")
      end
      crud.delete(self.workspace, dao_factory.workspaces)
    end,
  },

  ["/workspaces/:workspace_name_or_id/entities"] = {
    before = function(self, dao_factory, helpers)
      self.params.workspace_name_or_id = ngx.unescape_uri(self.params.workspace_name_or_id)
      crud.find_workspace_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      if self.params.resolve then
        local entities_hash = rbac.resolve_workspace_entities({ self.workspace.id })

        local e = setmetatable({}, cjson.empty_array_mt)
        for i = 1, #entities_hash do
          e[i] = entities_hash[i]
        end

        return helpers.responses.send_HTTP_OK(e)
      else
        local entities, err = dao_factory.workspace_entities:find_all({
          workspace_id = self.workspace.id,
        })
        if err then
          return helpers.yield_error(err)
        end

        return helpers.responses.send_HTTP_OK({
          data = entities,
          total = #entities,
        })
      end
    end,

    POST = function(self, dao_factory, helpers)

      if not self.params.entities then
        return helpers.responses.send_HTTP_BAD_REQUEST("must provide >= entity")
      end


      -- duplication check
      local existing_entities, err = dao_factory.workspace_entities:find_all({
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

        -- circular reference check
        local refs, err = dao_factory.workspace_entities:find_all({
          workspace_id = e,
          entity_id = self.workspace.id,
        })
        if err then
          return helpers.yield_error(err)
        end
        if #refs > 0 then
          local err = "Attempted to create circular reference (workspace " ..
                      "'" .. e .. "' already references '" ..
                      self.workspace.id .. "')"
          return helpers.responses.send_HTTP_CONFLICT(err)
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

    DELETE = function(self, dao_factory, helpers)
      if not self.params.entities then
        return helpers.responses.send_HTTP_BAD_REQUEST("must provide >= entity")
      end

      local entity_ids = utils.split(self.params.entities, ",")

      for i = 1, #entity_ids do
        local e = entity_ids[i]
        local ws_e, err = dao_factory.workspace_entities:find_all({
          workspace_id = self.workspace.id,
          entity_id = e,
        })
        if err then
          return helpers.yield_error(err)
        end

        for _, row in ipairs(ws_e) do
          local _, err = dao_factory.workspace_entities:delete(row)
          if err then
            return helpers.yield_error(err)
          end
        end

        workspaces.inc_counter(dao_factory, self.workspace.id, ws_e[1].entity_type, -1)
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },

  ["/workspaces/:workspace_name_or_id/entities/:entity_id"] = {
    before = function(self, dao_factory, helpers)
      self.params.workspace_name_or_id = ngx.unescape_uri(self.params.workspace_name_or_id)
      crud.find_workspace_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local e, err = dao_factory.workspace_entities:find_all({
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

      return e and helpers.responses.send_HTTP_OK(e) or
        helpers.responses.send_HTTP_NOT_FOUND()
    end,

    DELETE = function(self, dao_factory, helpers)
      local e, err = dao_factory.workspace_entities:find_all({
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
        local _, err = dao_factory.workspace_entities:delete(row)
        if err then
          return helpers.yield_error(err)
        end
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },
  ["/workspaces/:workspace_name_or_id/meta"] = {
    before = function(self, dao_factory, helpers)
      self.params.workspace_name_or_id =
        ngx.unescape_uri(self.params.workspace_name_or_id)
      crud.find_workspace_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local counts, err = workspaces.counts(self.workspace.id)
      if not counts then
        helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      return helpers.responses.send_HTTP_OK({counts = counts})
    end
  },

}
