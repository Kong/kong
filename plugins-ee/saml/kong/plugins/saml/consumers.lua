-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong          = kong
local ngx           = ngx

local log           = require "kong.plugins.saml.log"
local constants     = require "kong.constants"

local null          = ngx.null
local set_header    = ngx.req.set_header

local function find_consumer(consumer_id)

    local consumer_cache_key = kong.db.consumers:cache_key(consumer_id)
    return kong.cache:get(consumer_cache_key, nil, kong.client.load_consumer, consumer_id, true)
end

local function set_consumer(ctx, consumer)
  local headers = constants.HEADERS

  if consumer then
    log("setting kong consumer context and headers")

    kong.client.authenticate(consumer)

    if consumer.id and consumer.id ~= null then
      set_header(headers.CONSUMER_ID, consumer.id)
    else
      set_header(headers.CONSUMER_ID, nil)
    end

    if consumer.custom_id and consumer.custom_id ~= null then
      set_header(headers.CONSUMER_CUSTOM_ID, consumer.custom_id)
    else
      set_header(headers.CONSUMER_CUSTOM_ID, nil)
    end

    if consumer.username and consumer.username ~= null then
      set_header(headers.CONSUMER_USERNAME, consumer.username)
    else
      set_header(headers.CONSUMER_USERNAME, nil)
    end
  end
end


return {
  find      = find_consumer,
  set       = set_consumer,
}
