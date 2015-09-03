local crud = require "kong.api.crud_helpers"
local timestamp = require "kong.tools.timestamp"
local constants = require "kong.constants"
local rate_limit_utils = require "kong.plugins.rate-limiting.utils"

local string_format = string.format

local function format_usage(usage)
  local usage_for_field
  local response_data = { rate = {} }
  local no_limit_value = constants.RATELIMIT.USAGE.NO_LIMIT_VALUE

  for k, field_name in ipairs(constants.RATELIMIT.PERIODS) do
    usage_for_field = usage[field_name] or {}
    response_data.rate[string_format("limit-%s", field_name)] = usage_for_field.limit or no_limit_value
    response_data.rate[string_format("remaining-%s", field_name)] = usage_for_field.remaining or no_limit_value
  end

  return response_data
end

return {

  ["/apis/:name_or_id/plugins/rate-limiting/usage/:key"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id

      local data, err = dao_factory.keyauth_credentials:find_by_keys({ key = self.params.key })
      if err then
        return helpers.yield_error(err)
      end

      self.credential = data[1]
      if not self.credential then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory, helpers)
      local current_timestamp = timestamp.get_utc()
      local identifier = self.credential.id or ngx.var.remote_addr

      -- get api and plugin configuration
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
      self.params.api_id = self.api.id
      self.params.name = "rate-limiting"
      crud.find_plugin_conf_by_api_id_and_name(self, dao_factory, helpers)

      -- Load current metric for configured period
      local usage, _ = rate_limit_utils.get_usage(self.api.id, identifier, current_timestamp, self.plugin.config or {})
      local response_data = format_usage(usage)
      return helpers.responses.send_HTTP_OK(response_data)
    end
  },
}
