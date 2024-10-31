-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local endpoints = require "kong.api.endpoints"
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
      local custom_id = args.custom_id

      if custom_id and type(custom_id) ~= "string" or custom_id == "" then
        return kong.response.exit(400, {
          message = "custom_id must be an unempty string",
        })
      end

      if args.tags then
        table.insert(next_url,
          "tags=" .. escape_uri(type(args.tags) == "table" and args.tags[1] or args.tags))
      end

      -- Search by custom_id: /consumers?custom_id=xxx
      if custom_id and not args.username then
        local opts, _, err_t = endpoints.extract_options(db, args, db.consumers.schema, "select")
        if err_t then
          return endpoints.handle_error(err_t)
        end

        local consumer, _, err_t = db.consumers:select_by_custom_id(custom_id, opts)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        ---EE [[
        if consumer and consumer.type ~= enums.CONSUMERS.TYPE.PROXY then
          kong.response.exit(404, { message = "Not Found" })
        end
        --]] EE

        return kong.response.exit(200, {
          data = setmetatable({ consumer }, cjson.array_mt),
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
  },
  --]] EE

  ["/consumers/:consumers/plugins"] = {
    ---[[ EE
    before = function(self, db)
      ee_api.routes_consumers_before(self, self.args.post)
    end,
    --]] EE
  },
}
