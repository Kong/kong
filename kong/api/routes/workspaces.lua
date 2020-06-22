local workspaces = require "kong.workspaces"
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
  local namespace_workspace = ngx.ctx.workspace

  -- call from default ws is ok.
  if namespace_workspace == kong.default_workspace then
    return true
  end

  if api_workspace and api_workspace.id == namespace_workspace then
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
      if workspaces.get_workspace_id() ~= kong.default_workspace then
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

      local counts, err = counters.counts(self.workspace.id)
      local empty = true
      for k, v in pairs(counts) do
        if v > 0 then
          empty = false
        end
      end


      if err then
        return kong.response.exit(500, {err})
      end
      if not empty then
        return kong.response.exit(400, {message = "Workspace is not empty"})
      end

      return parent()
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
