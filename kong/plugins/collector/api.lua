local backend = require "kong.plugins.collector.backend"
local cjson   = require "cjson"
local utils = require "kong.tools.utils"

local function build_params_with_workspace(workspace_name)
  local query = kong.request.get_query()
  local args = kong.table.merge(query, { workspace_name = workspace_name })
  return utils.encode_args(args)
end

local function collector_url()
  local rows = kong.db.plugins:select_all({ name = "collector" })
  if rows[1] then
    local config = rows[1].config
    if config.https then
      return string.format("https://%s:%d", config.host, config.port)
    else
      return string.format("http://%s:%d", config.host, config.port)
    end
  end
  return nil, "No collector plugin found."
end

local function is_workspace_rule(workspace_name, rule)
  if rule.workspace_name ~= cjson.null and rule.workspace_name ~= workspace_name then
    return false
  elseif rule.service_id ~= cjson.null then
    local service = kong.db.services:select({ id = rule.service_id })
    if not service then
      return false
    end
  elseif rule.route_id ~= cjson.null then
    local route = kong.db.routes:select({ id = rule.route_id })
    if not route then
      return false
    end
  end
  return true
end

local function filter_workspace_rules(workspace_name, rules)
  local filtered = {}
  for _, value in ipairs(rules) do
    if is_workspace_rule(workspace_name, value) then
      table.insert(filtered, value)
    end
  end
  if next(filtered) == nil then
    return cjson.encode(cjson.empty_array)
  else
    return filtered
  end
end

local function set_workspace_url(self, db)
  local collector_url, err = collector_url()
  if err then
    kong.log.notice(err)
    kong.response.exit(428, { message = "No collector plugin found." })
  end
  self.collector_url = collector_url
end

return {
  ["/collector/status"] = {
    before = set_workspace_url,
    GET = function(self, db)
      local res, err = backend.http_request("GET", self.collector_url .. "/status")
      if err then
        kong.log.notice(err)
        kong.response.exit(500, { message = "Communication with collector failed." })
      else
        return kong.response.exit(res.status, res.body)
      end
    end
  },
  ["/collector/alerts"] = {
    before = set_workspace_url,
    GET = function(self, db)
      local query = build_params_with_workspace(self.url_params.workspace_name)
      local res, err = backend.http_request("GET", self.collector_url .. "/alerts?" .. query)

      if err then
        kong.log.notice(err)
        kong.response.exit(500, { message = "Communication with collector failed." })
      else
        return kong.response.exit(res.status, res.body)
      end
    end
  },
  ["/collector/alerts/config"] = {
    before = set_workspace_url,
    GET = function(self, db)
      local path = self.collector_url .. "/alerts/config"
      local query = build_params_with_workspace(self.url_params.workspace_name)
      if query then
        path = path .. "?" .. query
      end

      local res, err = backend.http_request("GET", path)
      if err then
        kong.log.notice(err)
        kong.response.exit(500, { message = "Communication with collector failed." })
      else
        local rules = filter_workspace_rules(self.url_params.workspace_name, cjson.decode(res.body))
        return kong.response.exit(res.status, rules)
      end
    end,
    POST = function(self, db)
      local path = self.collector_url .. "/alerts/config"
      local workspace_name = self.url_params.workspace_name
      local params = kong.table.merge(self.params, { workspace_name = workspace_name })
      local res, err = backend.http_request("POST", path, params)

      if err then
        kong.log.notice(err)
        kong.response.exit(500, { message = "Communication with collector failed." })
      else
        return kong.response.exit(res.status, res.body)
      end
    end,
  },
  ["/collector/alerts/config/:id[%d]"] = {
    before = function(self, db)
      set_workspace_url(self, db)
      local path = self.collector_url .. "/alerts/config/" .. self.params.id
      local res, err = backend.http_request(ngx.req.get_method(), path, self.params)

      if err then
        kong.log.notice(err)
        kong.response.exit(500, { message = "Communication with collector failed." })
      else
        return kong.response.exit(res.status, res.body)
      end
    end,
    GET = function(self, db) end,
    PATCH = function(self, db) end,
    DELETE = function(self, db) end,
  },
  ["/service_maps"] = {
    before = set_workspace_url,
    GET = function(self, db)
      local query = build_params_with_workspace(self.url_params.workspace_name)
      local path = self.collector_url .. "/alerts?" .. query
      local res, err = backend.http_request("GET", path)

      if err then
        kong.log.notice(err)
        kong.response.exit(500, { message = "Communication with collector failed." })
      else
        return kong.response.exit(res.status, res.body)
      end
    end
  }
}
