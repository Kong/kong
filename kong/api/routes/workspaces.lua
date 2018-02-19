local cjson = require "cjson"
local crud  = require "kong.api.crud_helpers"
local utils = require "kong.tools.utils"
local rbac  = require "kong.rbac"
local workspaces = require "kong.workspaces"


-- given an entity ID, look up its entity collection name;
-- it is only called if the user does not pass in an entity_type
local function resolve_entity_type(dao_factory, entity_id)
  local workspaceable = workspaces.get_workspaceable_relations()
  for relation, pk in pairs(workspaceable) do
    local row, err = dao_factory[relation]:find_all{[pk] = entity_id}
    if err then
      return nil, err
    end
    if row[1] then
      return relation
    end
  end
  return false, "entity does not belong to any relation"
end


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

    DELETE = function(self, dao_factory, helpers)
      if self.workspace.name == "default" then
        return helpers.responses.send_HTTP_METHOD_NOT_ALLOWED()
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
        local entity_type, err = resolve_entity_type(dao_factory, entity_ids[i])
        -- database error
        if entity_type == nil then
          return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
        end
        -- entity doesn't exist
        if entity_type == false then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)
        end

        local row, err = dao_factory.workspace_entities:insert({
          workspace_id = self.workspace.id,
          entity_id = entity_ids[i],
          entity_type = entity_type,
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
