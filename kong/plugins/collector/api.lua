local backend = require "kong.plugins.collector.backend"

local function backend_data()
    local rows = kong.db.plugins:select_all({ name = "collector" })
    return rows[1]
end

local function workspace_id_from_request(request)
    local row = kong.db.workspaces:select_by_name(request.url_params.workspace_name)
    return row.id
end

return {
  ["/collector/status"] = {
    GET = function(self, db)
      local backend_data = backend_data()

      if not backend_data then
        return kong.response.exit(404, { message = "No configuration found." })
      end

      local query = kong.request.get_raw_query()
      local res, err = backend.http_get(
        backend_data.config.host,
        backend_data.config.port,
        backend_data.config.connection_timeout,
        "/status",
        query
      )
      if err then
        error("communication with brain/immunity failed: " .. tostring(err))
      else
        return kong.response.exit(res.status, res:read_body())
      end
    end
  },
  ["/collector/alerts"] = {
    GET = function(self, db)
      local row =  backend_data()

      if not row then
        return kong.response.exit(404, { message = "No configuration found." })
      end

      local query = kong.request.get_raw_query()
      local workspace_name = self.url_params.workspace_name
      if query then
        query = query .. '&workspace_name=' .. workspace_name
      else
        query = 'workspace_name=' .. workspace_name
      end

      local res, err = backend.http_get(
        row.config.host,
        row.config.port,
        row.config.connection_timeout,
        "/alerts",
        query
      )

      if err then
        error("communication with brain/immunity failed: " .. tostring(err))
      else
        return kong.response.exit(res.status, res:read_body())
      end
    end
  },
  ["/service_maps"] = {
    GET = function(self, db)
      local workspace_id = workspace_id_from_request(self)
      local service_map = kong.db.service_maps:select({ workspace_id = workspace_id })

      if not service_map then
        return kong.response.exit(404, { message = "Not found" })
      end

      return kong.response.exit(200, { data = { service_map } })
    end,

    POST = function(self, db)
      local workspace_id = workspace_id_from_request(self)
      local service_map, err = kong.db.service_maps:upsert(
        { workspace_id = workspace_id },
        { service_map = self.params.service_map }
      )

      if err then
        error("error while updating service map: " .. tostring(err))
      end

      return kong.response.exit(200, service_map)
    end
  }
}
