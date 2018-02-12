local cjson = require "cjson"
local crud  = require "kong.api.crud_helpers"
local utils = require "kong.tools.utils"
local rbac  = require "kong.rbac"

return {
  ["/workspaces/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.workspaces)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.workspaces)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.workspaces)
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

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.workspaces, self.workspace)
    end,

    DELETE = function(self, dao_factory)
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


      -- which one of these are workspace references?
      local ws_ref = {}


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

        local ws_ref_row, err = dao_factory.workspaces:find({id = e})
        if err then
          return helpers.yield_error(err)
        end
        if ws_ref_row then
          ws_ref[e] = true
        end
      end


      -- yayyyy, no fuckup! now do the thing
      local res = {}
      for i = 1, #entity_ids do
        local row, err = dao_factory.workspace_entities:insert({
          workspace_id = self.workspace.id,
          entity_id = entity_ids[i],
          entity_type = ws_ref[entity_ids[i]] and "workspace" or "entity",
        })
        if err then
          helpers.yield_error(err)
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

        local _, err = dao_factory.workspace_entities:delete({
          workspace_id = self.workspace.id,
          entity_id = e,
        })
        if err then
          return helpers.yield_error(err)
        end
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
      local e, err = dao_factory.workspace_entities:find({
        workspace_id = self.workspace.id,
        entity_id = self.params.entity_id,
      })
      if err then
        return helpers.yield_error(err)
      end

      return e and helpers.responses.send_HTTP_OK(e) or
                   helpers.responses.send_HTTP_NOT_FOUND()
    end,

    DELETE = function(self, dao_factory, helpers)
      local e, err = dao_factory.workspace_entities:find({
        workspace_id = self.workspace.id,
        entity_id = self.params.entity_id,
      })
      if err then
        return helpers.yield_error(err)
      end

      if e then
        local _, err = dao_factory.workspace_entities:delete({
          workspace_id = self.workspace.id,
          entity_id = self.params.entity_id,
        })
        if err then
          return helpers.yield_error(err)
        end

        return helpers.responses.send_HTTP_NO_CONTENT()

      else
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,
  }
}
