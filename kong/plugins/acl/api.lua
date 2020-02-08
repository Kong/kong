local endpoints   = require "kong.api.endpoints"
local utils       = require "kong.tools.utils"


local ngx = ngx
local kong = kong
local escape_uri = ngx.escape_uri
local unescape_uri = ngx.unescape_uri


return {
  ["/consumers/:consumers/acls/:acls"] = {
    schema = kong.db.acls.schema,
    before = function(self, db, helpers)
      local group = unescape_uri(self.params.acls)
      if not utils.is_valid_uuid(group) then
        local consumer_id = unescape_uri(self.params.consumers)

        if not utils.is_valid_uuid(consumer_id) then
          local consumer, _, err_t = endpoints.select_entity(self, db, db.consumers.schema)
          if err_t then
            return endpoints.handle_error(err_t)
          end

          if not consumer then
            return kong.response.exit(404, { message = "Not found" })
          end

          consumer_id = consumer.id
        end

        local cache_key = db.acls:cache_key(consumer_id, group)
        local acl, _, err_t = db.acls:select_by_cache_key(cache_key)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        if acl then
          self.params.acls = escape_uri(acl.id)
        else
          if self.req.method ~= "PUT" then
            return kong.response.exit(404, { message = "Not found" })
          end

          self.params.acls = utils.uuid()
        end

        self.params.group = group
      end
    end,

    PUT = function(self, db, helpers, parent)
      if not self.args.post.group and self.params.group then
        self.args.post.group = self.params.group
      end

      return parent()
    end
  }
}
