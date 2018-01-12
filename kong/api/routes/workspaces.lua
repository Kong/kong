local crud = require "kong.api.crud_helpers"

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
}
