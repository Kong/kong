-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local ratelimiting = require("kong.tools.public.rate-limiting").new_instance("ai-rate-limiting-advanced", { redis_config_version = "v2" })


local human_window_size_lookup = {
  [1]        = "second",
  [60]       = "minute",
  [3600]     = "hour",
  [86400]    = "day",
  [2592000]  = "month",
  [31536000] = "year",
}

-- Add draft headers for rate limiting RFC
-- https://tools.ietf.org/html/draft-polli-ratelimit-headers-02
local HEADERS = {
  X_RATELIMIT_LIMIT = "X-AI-RateLimit-Limit",
  X_RATELIMIT_REMAINING = "X-AI-RateLimit-Remaining",
  X_RATELIMIT_RESET = "X-AI-RateLimit-Reset",
  X_RATELIMIT_RETRY_AFTER = "X-AI-RateLimit-Retry-After",
  X_RATELIMIT_QUERY_COST = "X-AI-RateLimit-Query-Cost",
}

local id_lookup = {
  ip = function()
    return kong.client.get_forwarded_ip()
  end,
  credential = function()
    return kong.client.get_credential() and
           kong.client.get_credential().id
  end,
  consumer = function()
    -- try the consumer, fall back to credential
    return kong.client.get_consumer() and
           kong.client.get_consumer().id or
           kong.client.get_credential() and
           kong.client.get_credential().id
  end,
  service = function()
    return kong.router.get_service() and
           kong.router.get_service().id
  end,
  header = function(conf)
    return kong.request.get_header(conf.header_name)
  end,
  path = function(conf)
    return kong.request.get_path() == conf.path and conf.path
  end,
  ["consumer-group"] = function (conf)
    local scoped_to_cg_id = conf.consumer_group_id
    if not scoped_to_cg_id then
      return nil
    end
    for _, cg in ipairs(kong.client.get_consumer_groups()) do
      if cg.id == scoped_to_cg_id then
        return cg.id
      end
    end
    return nil
  end
}



return {
  id_lookup = id_lookup,
  ratelimiting = ratelimiting,
  human_window_size_lookup = human_window_size_lookup,
  HEADERS = HEADERS,
}

