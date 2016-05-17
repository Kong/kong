local influxdb_log_schema = require "kong.plugins.http-log.schema"

influxdb_log_schema.fields.content_type.default = "application/x-www-form-urlencoded"
return influxdb_log_schema
