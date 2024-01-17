local cjson                        = require("cjson.safe")
local constants                    = require("kong.constants")

local ngx                          = ngx
local kong                         = kong
local pcall                        = pcall
local type                         = type
local tostring                     = tostring

local digest = require("resty.openssl.digest")
local hasher = digest.new("sha256")
local to_hex = require("resty.string").to_hex
local reload_plugins = require "kong.clustering.services.plugin_streaming".reload_plugins

local assets_prefix = (kong.configuration.prefix or require("pl.path").abspath(ngx.config.prefix())) .. "/streamed_assets/"

local routes = {
  ["/plugin_streaming/register_assets"] = {
    PUT = function(self)
      if not self.params.plugin_name then
        return kong.response.exit(400, { message = "Missing name for plugin" })
      end

      local url
      local content
      local downloaded_file
      if self.params.content then
        url = "kong://" .. self.params.name
        content = self.params.content

        if not content then
          return kong.response.exit(400, { message = "File is empty" })
        end

        downloaded_file = "/tmp/cp_plugin_stream_assets/_" .. self.params.name
        local f = io.open(downloaded_file, "w")
        assert(f:write(content))
        assert(f:close())
      end

      hasher:reset()
      local metadata = {
        plugin_name = self.params.plugin_name,
        url = url,
        size = #content,
        sha256sum = to_hex(assert(hasher:final(content))),
      }

      assert(ngx.shared.kong:set("plugin_streaming_assets::" .. self.params.name, cjson.encode(metadata)))

      os.execute("mkdir -p " .. assets_prefix .. " ; tar zxvf " .. downloaded_file .. " -C " .. assets_prefix)
      ngx.log(ngx.ERR, ">> file extracts")
      local ok, err = reload_plugins(nil, self.params.plugin_name)
      if not ok then
        return kong.response.exit(400, { message = "Failed to load new plugin " .. err })
      end

      return kong.response.exit(200, { result = {
        name = self.params.name,
        metadata = metadata,
      },  })
    end,
  },

  ["/plugin_streaming/register_assets/:asset_id"] = {
    GET = function(self)
      local name = self.params.asset_id
      local metadata = ngx.shared.kong:get("plugin_streaming_assets::" .. name)
      if not metadata then
        return kong.response.exit(400, { message = "Not registered asset" .. name, })
      end

      return kong.response.exit(200, { result = {
        name = self.params.asset_id,
        metadata = cjson.decode(metadata),
      }}  )
    end,
  },

  ["/plugin_streaming/assets/:asset_id/node/:node_id"] = {
    PUT = function(self)
      local name = self.params.asset_id
      local metadata = ngx.shared.kong:get("plugin_streaming_assets::" .. name)
      if not metadata then
        return kong.response.exit(400, { message = "Not registered asset" .. name, })
      end
      metadata = cjson.decode(metadata)
      local contentfp

      if metadata.url:sub(1, 7) == "kong://" then
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
}


return routes
