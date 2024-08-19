-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong
local producers = require "kong.enterprise_edition.kafka.plugins.producers"
local meta = require "kong.meta"
local cjson_encode = require("cjson").encode

local ngx_encode_base64 = ngx.encode_base64

local CONFLUENT_CLIENT_ID = "cwc|001f100001XcA82AAF"

local ConfluentHandler = {}

ConfluentHandler.PRIORITY = 752
ConfluentHandler.VERSION = meta.core_version


local raw_content_types = {
  ["text/plain"] = true,
  ["text/html"] = true,
  ["application/xml"] = true,
  ["text/xml"] = true,
  ["application/soap+xml"] = true,
}


local function build_kafka_message_from_request(conf)
  local method
  if conf.forward_method then
    method = kong.request.get_method()
  end

  local headers
  if conf.forward_headers then
    headers = kong.request.get_headers()
  end

  local uri, uri_args
  if conf.forward_uri then
    uri      = kong.request.get_path_with_query()
    uri_args = kong.request.get_query()
  end

  local body, body_args, body_base64
  if conf.forward_body then
    body = kong.request.get_raw_body()
    local err
    body_args, err = kong.request.get_body()
    if err and err:match("content type") then
      body_args = {}
      local content_type = kong.request.get_header("content-type")
      if not raw_content_types[content_type] then
        -- don't know what this body MIME type is, base64 it just in case
        body = ngx_encode_base64(body)
        body_base64 = true
      end
    end
  end

  return cjson_encode({
    method      = method,
    headers     = headers,
    uri         = uri,
    uri_args    = uri_args,
    body        = body,
    body_args   = body_args,
    body_base64 = body_base64,
  })
end

function ConfluentHandler:access(conf)
  local message, err = build_kafka_message_from_request(conf)
  if not message then
    return producers.handle_error({
            status_code = 500,
            internal_error = "could not build a Kafka message from request " .. err,
            external_error = "could not build Kafka message"
        })
  end

  -- Translate config to producer config as this plugin needs a simplified schema.
  local config = {
    topic = conf.topic,
    bootstrap_servers = conf.bootstrap_servers,
    timeout = conf.timeout,
    keepalive = conf.keepalive,
    keepalive_enabled = conf.keepalive_enabled,
    authentication = {
      mechanism = "PLAIN",
      strategy = "sasl",
      user = conf.cluster_api_key,
      password = conf.cluster_api_secret,
      -- confluent_cloud_api_key = conf.confluent_cloud_api_key,
      -- confluent_cloud_api_secret = conf.confluent_cloud_api_secret,
    },
    security = {
      ssl = true,
    },
    client_id = CONFLUENT_CLIENT_ID,
  }
  local ok, s_err = producers.send_message(config, message)
  if not ok then
    return producers.handle_error(s_err)
  end

  return kong.response.exit(200, { message = "message sent" })
end

return ConfluentHandler
