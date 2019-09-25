local oas_config   = require "kong.enterprise_edition.oas_config"
local core_handler = require "kong.runloop.handler"
local oas2kong     = require "kong.enterprise_edition.openapi2kong"
local singletons   = require "kong.singletons"
local declarative  = require "kong.db.declarative"
local uuid         = require("kong.tools.utils").uuid

local kong = kong


local function rebuild_routes()
  local old_wss = ngx.ctx.workspaces
  ngx.ctx.workspaces = {}
  core_handler.build_router(singletons.db, uuid())
  ngx.ctx.workspaces = old_wss
end


return {
  ["/oas-config/v2"] = {
    POST = function(self, dao, helpers)
      rebuild_routes()
      ngx.req.read_body()

      local spec = ngx.req.get_body_data()
      local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or ""

      local conf, err = oas2kong.convert_spec(spec, {})
      if err then
        return kong.response.exit(400, { message = "Error converting OpenAPI", reason = err })
      end

      local dc, err = declarative.new_config(singletons.configuration)
      if not dc then
        return kong.response.exit(400, { message = "Error generating config", reason = err })
      end

      local dc_table, err, _, _, _, _ = dc:parse_table(conf)
      if not dc_table then
        return kong.response.exit(400, { message = "Parsing failed", reason = err })
      end

      local ok, err = declarative.load_into_db(dc_table, workspace.name)
      if not ok then
        return kong.response.exit(400, { message = "Import failed", reason = err })
      end

      return kong.response.exit(201, { message = "Success" })
    end,
  },

  ["/oas-config"] = {
    POST = function(self, dao, helpers)
      rebuild_routes()

      local res, err_t = oas_config.post_auto_config(self.params.spec)
      if err_t then
        return kong.response.exit(err_t.code, { message = err_t.message })
      end

      return kong.response.exit(201, res)
    end,

    PATCH = function(self, dao, helpers)
      local ok, err_t, res, resources_created = oas_config.patch_auto_config(self.params.spec, self.params.recreate_routes)
      if not ok then
        return kong.response.exit(err_t.code, { message = err_t.message })
      end

      if resources_created then
        return kong.response.exit(201, res)
      end

      return kong.response.exit(200, res)
    end,
  }
}
