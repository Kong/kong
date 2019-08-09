local getters = require "kong.portal.render_toolset.getters"
local cjson   = require "cjson.safe"


local PortalConfig = {}


function PortalConfig:developer_meta_fields()
  local ws_conf = getters.select_kong_config()
  local ctx = cjson.decode(ws_conf.PORTAL_DEVELOPER_META_FIELDS)

  local function map_cb(item)
    local SCHEMA_TO_FIELD_TYPE = { string = "text", number = "number" }
    local type = item.is_email and "email" or SCHEMA_TO_FIELD_TYPE[item.validator.type]

    return {
      name = item.title,
      label = item.label,
      required = item.validator.required,
      type = type,
    }
  end

  return self
          :set_ctx(ctx)
          :map(map_cb)
          :next()
end


return PortalConfig
