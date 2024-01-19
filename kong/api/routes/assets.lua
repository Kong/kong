local cjson                        = require("cjson.safe")
local constants                    = require("kong.constants")
local endpoints                    = require "kong.api.endpoints"
local utils                        = require "kong.tools.utils"

local digest                       = require("resty.openssl.digest")
local hasher                       = digest.new("sha256")
local to_hex                       = require("resty.string").to_hex
local pl_path                      = require "pl.path"
local reload_plugins               = require "kong.clustering.services.plugin_streaming".reload_plugins

local ngx                          = ngx
local kong                         = kong
local pcall                        = pcall
local type                         = type
local tostring                     = tostring
local assets_schema                = kong.db.assets.schema

local assets_prefix = (kong.configuration.prefix or require("pl.path").abspath(ngx.config.prefix())) .. "/streamed_assets/"

local function prepare_assets(self, db)
  local url
  local content
  local downloaded_file

  local args = self.args.post
  -- PUT /assets/:assets, or POST form arg
  local name = self.params.assets or args.name
  if not name then
    return kong.response.exit(400, { message = "Name is required" })
  end

  local metadata = args.metadata or {}

  if args.content then
    url = "kong://" .. name
    content = args.content

    if not content then
      return kong.response.exit(400, { message = "File is empty" })
    end

    hasher:reset()
    metadata.sha256sum = to_hex(assert(hasher:final(content)))
    os.execute("mkdir -p " .. assets_prefix)
    downloaded_file = assets_prefix .. "/" .. metadata.sha256sum .. ".assetbundle"
    local f = io.open(downloaded_file, "w")
    assert(f:write(content))
    assert(f:close())
  else
    return kong.response.exit(400, { message = "Content is required" })
  end

  metadata.type = metadata.type or "plugin"
  metadata.size = #content

  args.metadata = metadata
  args.content = nil
  args.url = url

  ngx.log(ngx.ERR, "--> self ", require("inspect")(args))

  os.execute("mkdir -p " .. assets_prefix .. " ; tar zxvf " .. downloaded_file .. " -C " .. assets_prefix)
  ngx.log(ngx.ERR, ">> file extracts")
end

local routes = {
  ["/assets"] = {
    schema  = assets_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(assets_schema),
      POST = function(self, db)
        prepare_assets(self, db)

        return endpoints.post_collection_endpoint(assets_schema)(self, db)
      end,
    }
  },

  ["/assets/:assets"] = {
    schema  = assets_schema,
    methods = {
      GET = endpoints.get_entity_endpoint(assets_schema),
      DELETE = endpoints.delete_entity_endpoint(assets_schema),
      PUT = function(self, db)
        prepare_assets(self, db)

        return endpoints.put_entity_endpoint(assets_schema)(self, db)
      end,
    },
  },

  ["/assets/:asset_id/node/:node_id"] = {
    methods = {
      PUT = function(self)
        local asset_entity, err = kong.db.assets:select(
          utils.is_valid_uuid(self.params.asset_id) and
          { id = self.params.asset_id } or
          { name = self.params.asset_id }
        )
    
        if err then
          return kong.response.exit(500, { message = "Failed to select assets: " .. err })
        elseif not asset_entity then
          return kong.response.exit(400, { message = "Not registered asset" .. name, })
        end
      
        local metadata = asset_entity.metadata
        local name = asset_entity.name

        local contentfp

        if asset_entity.url:sub(1, 7) == "kong://" then
          contentfp = assert(io.open("/tmp/cp_plugin_stream_assets/_" .. name))
        else
          return kong.response.exit(500, { message = "Unresolved asset URL", })
        end

        if not contentfp then
          return kong.response.exit(500, { message = "Unresupported storage", })
        end

        ngx.log(ngx.ERR, "-> stream_metadata")

        local res, err = kong.rpc:call(self.params.node_id, "kong.plugin_streaming.v1.stream_asset_metadata", name, metadata)
        if not res then
          return kong.response.exit(500, { message = err, })
        end

        ngx.log(ngx.ERR, "-> stream_content")

        local seq = 1
        while true do
          local partial = contentfp:read(2 * 1024 * 1024) -- 2M
          if not partial then
            break
          end
          res, err = kong.rpc:call(self.params.node_id, "kong.plugin_streaming.v1.stream_asset_content", name, partial, seq)
          if not res then
            return kong.response.exit(500, { message = err, })
          end
          seq = seq + 1
        end

        ngx.log(ngx.ERR, "-> request_reload")

        res, err = kong.rpc:call(self.params.node_id, "kong.plugin_streaming.v1.reload_plugins", metadata.plugin_name)
        if not res then
          return kong.response.exit(500, { message = err, })
        end

        return kong.response.exit(200, { result = "awesome!",  })
      end,
    },
  },
}


return routes
