local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local pl_string = require "pl.stringx"
local pl_table = require "pl.tablex"
local url = require "socket.url"

local PathRouterHandler = BasePlugin:extend()

function PathRouterHandler:new()
  PathRouterHandler.super.new(self, " PathRouter")
end

function PathRouterHandler:access(conf)
  PathRouterHandler.super.access(self)

  if conf.querystring and conf.querystring.mappings then
    local querystring_parameters = ngx.req.get_uri_args()
    for _, mapping in ipairs(conf.querystring.mappings) do
      if querystring_parameters[mapping.name] and querystring_parameters[mapping.name] == mapping.value then

        -- Split the paths
        local forward_path_parts = pl_string.split(mapping.forward_path, "?")
        if #forward_path_parts == 2 then
          -- Merge the querystring parameters
          querystring_parameters = pl_table.merge(querystring_parameters, ngx.decode_args(forward_path_parts[2]), true)
        end

        local parsed_url = url.parse(ngx.ctx.upstream_url)
        local newurl = ngx.re.gsub(ngx.ctx.upstream_url, parsed_url.path, forward_path_parts[1])
        if newurl then
          -- Set the upstream URL
          ngx.ctx.upstream_url = newurl
          if mapping.strip then
            querystring_parameters[mapping.name] = nil
          end
        else
          return responses.send_HTTP_INTERNAL_SERVER_ERROR()
        end

        -- Set the new querystring params
        ngx.req.set_uri_args(querystring_parameters)
        break
      end
    end
  end
end

PathRouterHandler.PRIORITY = 801

return PathRouterHandler
