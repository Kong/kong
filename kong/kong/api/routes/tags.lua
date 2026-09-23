local endpoints   = require "kong.api.endpoints"

local fmt = string.format
local escape_uri  = ngx.escape_uri


return {
  ["/tags/:tags"] = {
    GET = function(self, db, helpers, parent)
      local data, _, err_t, offset =
        endpoints.page_collection(self, db, db.tags.schema, "page_by_tag")

      if err_t then
        return endpoints.handle_error(err_t)
      end

      local next_page
      if offset then
        next_page = fmt("/tags/%s?offset=%s", self.params.tags, escape_uri(offset))

      else
        next_page = ngx.null
      end

      return kong.response.exit(200, {
        data   = data,
        offset = offset,
        next   = next_page,
      })
    end,
  },
}
