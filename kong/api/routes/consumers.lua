local endpoints = require "kong.api.endpoints"
local reports = require "kong.reports"
local utils = require "kong.tools.utils"
local cjson = require "cjson"

local enums = require "kong.enterprise_edition.dao.enums"
local ee_api = require "kong.enterprise_edition.api_helpers"

local kong = kong
local null = ngx.null
local kong = kong
local consumers_schema = kong.db.consumers.schema
local fmt = string.format
local escape_uri  = ngx.escape_uri

return {
  ["/consumers"] = {
    ---EE [[
    --Restrict endpoints from editing consumer.type or non-proxy consumers
    before = function (self)
      ee_api.routes_consumers_before(self, self.args.post, true)
    end,
    --]] EE

    GET = function(self, db, helpers, parent)
      local next_url = {}
      local next_page = null
      local args = self.args.uri

      if args.tags then
        table.insert(next_url,
          "tags=" .. (type(args.tags) == "table" and args.tags[1] or args.tags))
      end

      -- Search by custom_id: /consumers?custom_id=xxx
      if args.custom_id then
        local opts = endpoints.extract_options(args, db.consumers.schema, "select")
        local consumer, _, err_t = db.consumers:select_by_custom_id(args.custom_id, opts)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        ---EE [[
        if consumer and consumer.type ~= enums.CONSUMERS.TYPE.PROXY then
          kong.response.exit(404, { message = "Not Found" })
        end
        --]] EE

        return kong.response.exit(200, {
          data = { consumer },
          next = null,
        })
      end

      ---EE [[
      -- paging consumers by the "proxy" type
      self.args.uri.type = enums.CONSUMERS.TYPE.PROXY
      local data, _, err_t, offset =
        endpoints.page_collection(self, db, consumers_schema, "page_by_type")

      if err_t then
        return endpoints.handle_error(err_t)
      end

      if offset then
        table.insert(next_url, fmt("offset=%s", escape_uri(offset)))
      end

      if next(next_url) then
        next_page = "/consumers?" .. table.concat(next_url, "&")
      end

      setmetatable(data, cjson.empty_array_mt)

      return kong.response.exit(200, {
        data   = data,
        offset = offset,
        next   = next_page,
      })
      --]] EE
    end
  },

  ---[[ EE
  -- override endpoint to allow for filtering of routes
  ["/consumers/:consumers"] = {
    schema = consumers_schema,
    before = function(self, db)
      ee_api.routes_consumers_before(self, self.args.post)
    end,
    methods = {
      GET = endpoints.get_entity_endpoint(consumers_schema),
      PUT  = endpoints.put_entity_endpoint(consumers_schema),
      PATCH  = endpoints.patch_entity_endpoint(consumers_schema),
      DELETE = endpoints.delete_entity_endpoint(consumers_schema),
    },
  },
  --]] EE

  ["/consumers/:consumers/plugins"] = {
    ---[[ EE
    before = function(self, db)
      ee_api.routes_consumers_before(self, self.args.post)
    end,
    --]] EE

    POST = function(_, _, _, parent)
      local post_process = function(data)
        local r_data = utils.deep_copy(data)
        r_data.config = nil
        r_data.e = "c"
        reports.send("api", r_data)
        return data
      end
      return parent(post_process)
    end,
  },
}
