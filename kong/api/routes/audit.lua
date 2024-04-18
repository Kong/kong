-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local endpoints = require "kong.api.endpoints"
local errors = require("kong.db.errors")
local date_tools = require("kong.tools.date")
local kong = kong


if not kong.configuration.audit_log then
  return {}
end

local function configure_sort_by_time_desc(self)
  if not self.args.uri.sort_by then
    self.args.uri.sort_by = "request_timestamp"

    if self.args.uri.sort_desc == nil then
      self.args.uri.sort_desc = true
    end
  end
end

local function parse_date_param(param)
  local number = tonumber(param)
  if number then
    return number
  end

  return date_tools.aip_date_to_timestamp(param)
end

local function process_before_and_after_aliases(self)
  if self.args.uri.before then
    local parse_before_param, err = parse_date_param(self.args.uri.before)
    if not parse_before_param then
      return endpoints.handle_error(
        errors:invalid_search_query(err)
      )
    end
    self.args.uri["request_timestamp[lt]"] = parse_before_param
    self.args.uri.before = nil
  end

  if self.args.uri.after then
    local parse_after_param, err = parse_date_param(self.args.uri.after)
    if not parse_after_param then
      return endpoints.handle_error(
        errors:invalid_search_query(err)
      )
    end
    self.args.uri["request_timestamp[gte]"] = parse_after_param
    self.args.uri.after = nil
  end
end


return {
  ["/audit/requests"] = {
    schema = kong.db.audit_requests.schema,
    methods = {
      GET = function(self, db, helpers)
        configure_sort_by_time_desc(self)
        process_before_and_after_aliases(self)
        return endpoints.get_collection_endpoint(kong.db.audit_requests.schema)(self, db, helpers)
      end
    }
  },

  ["/audit/objects"] = {
    schema = kong.db.audit_objects.schema,
    methods = {
      GET = function(self, db, helpers)
        configure_sort_by_time_desc(self)
        process_before_and_after_aliases(self)
        return endpoints.get_collection_endpoint(kong.db.audit_objects.schema)(self, db, helpers)
      end
    }
  },
}
