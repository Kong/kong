-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local unexpected = require "kong.plugins.openid-connect.unexpected"
local claims     = require "kong.plugins.openid-connect.claims"
local cache      = require "kong.plugins.openid-connect.cache"
local log        = require "kong.plugins.openid-connect.log"


local constants  = require "kong.constants"


local type       = type
local concat     = table.concat
local tostring   = tostring
local null       = ngx.null
local set_header = ngx.req.set_header


local function find_consumer(token, claim, anonymous, consumer_by, ttl, by_username_ignore_case)
  if not token then
    return nil, "token for consumer mapping was not found"
  end

  if type(token) ~= "table" then
    return nil, "opaque token cannot be used for consumer mapping"
  end

  local payload = token.payload

  if not payload then
    return nil, "token payload was not found for consumer mapping"
  end

  if type(payload) ~= "table" then
    return nil, "invalid token payload was specified for consumer mapping"
  end

  local subject = claims.find(payload, claim)
  if not subject then
    if type(claim) == "table" then
      return nil, "claim (" .. concat(claim, ",") .. ") was not found for consumer mapping"
    end

    return nil, "claim (" .. tostring(claim) .. ") was not found for consumer mapping"
  end

  return cache.consumers.load(subject, anonymous, consumer_by, ttl, by_username_ignore_case)
end


local function set_consumer(ctx, consumer, credential)
  local head = constants.HEADERS

  if consumer then
    log("setting kong consumer context and headers")

    if credential and credential ~= null then
      kong.client.authenticate(consumer, credential)

    else
      set_header(head.ANONYMOUS, nil)

      if consumer.id and consumer.id ~= null then
        local lcredential = {
          consumer_id = consumer.id
        }
        kong.client.authenticate(consumer, lcredential)
      else
        kong.client.authenticate(consumer)
      end
    end

    if consumer.id and consumer.id ~= null then
      set_header(head.CONSUMER_ID, consumer.id)
    else
      set_header(head.CONSUMER_ID, nil)
    end

    if consumer.custom_id and consumer.custom_id ~= null then
      set_header(head.CONSUMER_CUSTOM_ID, consumer.custom_id)
    else
      set_header(head.CONSUMER_CUSTOM_ID, nil)
    end

    if consumer.username and consumer.username ~= null then
      set_header(head.CONSUMER_USERNAME, consumer.username)
    else
      set_header(head.CONSUMER_USERNAME, nil)
    end

  elseif not ctx.authenticated_credential then
    log("removing possible remnants of anonymous")

    ctx.authenticated_consumer   = nil
    ctx.authenticated_credential = nil

    set_header(head.CONSUMER_ID,        nil)
    set_header(head.CONSUMER_CUSTOM_ID, nil)
    set_header(head.CONSUMER_USERNAME,  nil)

    set_header(head.ANONYMOUS,          nil)
  end
end


local function set_anonymous(ctx, anonymous, client)
  local consumer_token = {
    payload = {
      id = anonymous
    }
  }

  local consumer, err = find_consumer(consumer_token, "id", true, nil, false)
  if type(consumer) ~= "table" then
    if err then
      return unexpected(client, "anonymous consumer was not found (", err, ")")

    else
      return unexpected(client, "anonymous consumer was not found")
    end
  end

  local head = constants.HEADERS

  ctx.authenticated_consumer   = consumer
  ctx.authenticated_credential = nil

  if consumer.id and consumer.id ~= null then
    set_header(head.CONSUMER_ID, consumer.id)
  else
    set_header(head.CONSUMER_ID, nil)
  end

  if consumer.custom_id and consumer.custom_id ~= null then
    set_header(head.CONSUMER_CUSTOM_ID, consumer.custom_id)
  else
    set_header(head.CONSUMER_CUSTOM_ID, nil)
  end

  if consumer.username and consumer.username ~= null then
    set_header(head.CONSUMER_USERNAME, consumer.username)
  else
    set_header(head.CONSUMER_USERNAME, nil)
  end

  set_header(head.ANONYMOUS, true)
end


return {
  find      = find_consumer,
  set       = set_consumer,
  anonymous = set_anonymous,
}
