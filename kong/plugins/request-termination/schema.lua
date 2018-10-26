local Errors = require "kong.dao.errors"

return {
  fields = {
    status_code = { type = "number", default = 503 },
    message = { type = "string" },
    content_type = { type = "string" },
    body = { type = "string" },
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    if plugin_t.status_code then
      if plugin_t.status_code < 100 or plugin_t.status_code > 599 then
        return false, Errors.schema("status_code must be between 100 .. 599")
      end
    end

    if plugin_t.message and plugin_t.message ~= ngx.null then
      if plugin_t.content_type or (plugin_t.body and plugin_t.body ~= ngx.null) then
        return false, Errors.schema("message cannot be used with content_type or body")
      end
    else
      if plugin_t.content_type and not plugin_t.body then
        return false, Errors.schema("content_type requires a body")
      end
    end

    return true
  end
}
