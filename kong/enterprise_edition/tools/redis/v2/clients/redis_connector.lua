-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local redis_connector = require "resty.redis.connector"
local redis_config_utils = require "kong.enterprise_edition.tools.redis.v2.config_utils"

local string_format   = string.format
local table_concat    = table.concat
local redis_proxy_custom_disabled_commands = redis_config_utils.redis_proxy_custom_disabled_commands


-- Create a connection with Redis; expects a table with
-- required parameters. Examples:
--
-- Redis:
--   {
--     host = "127.0.0.1",
--     port = 6379,
--   }
--
-- Redis Sentinel:
--   {
--      sentinel_role = "master",
--      sentinel_master = "mymaster",
--      sentinel_nodes = {
--        { host = "127.0.0.1", port = 26379}
--      }
--   }
local function connect(conf, connect_opts)
  -- use lua-resty-redis-connector for sentinel and plain redis
  local rc = redis_connector.new({
    host               = conf.host,
    port               = conf.port,
    connect_timeout    = conf.connect_timeout,
    send_timeout       = conf.send_timeout,
    read_timeout       = conf.read_timeout,
    master_name        = conf.sentinel_master,
    role               = conf.sentinel_role,
    sentinels          = conf.sentinel_nodes,
    username           = conf.username,
    password           = conf.password,
    sentinel_username  = conf.sentinel_username,
    sentinel_password  = conf.sentinel_password,
    db                 = conf.database,
    connection_options = connect_opts,
    -- https://github.com/ledgetech/lua-resty-redis-connector?tab=readme-ov-file#proxy-mode
    connection_is_proxied = conf.connection_is_proxied,
    disabled_commands     = redis_proxy_custom_disabled_commands[conf.redis_proxy_type],
  })

  -- When trying to connect on multiple hosts, the resty-redis-connector will record the errors
  -- inside a third return value, see https://github.com/ledgetech/lua-resty-redis-connector/blob
  -- /03dff6da124ec0a6ea6fa1f7fd2a0a47dc27c33d/lib/resty/redis/connector.lua#L343-L344
  -- for more details.
  -- Note that this third return value is not recorded in the official documentation
  local red, err, previous_errors = rc:connect()
  if not red or err then
    if previous_errors then
      err = string_format("current errors: %s, previous errors: %s",
                                    err, table_concat(previous_errors, ", "))
    end

    return nil, err
  end

  return red, nil
end

return {
  connect = connect
}
