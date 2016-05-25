local utils = require "kong.tools.utils"
local http_log_schema = require "kong.plugins.http-log.schema"

local influxdb_log_schema = utils.deep_copy(http_log_schema)

influxdb_log_schema.fields.content_type.default = "application/x-www-form-urlencoded"

return influxdb_log_schema
