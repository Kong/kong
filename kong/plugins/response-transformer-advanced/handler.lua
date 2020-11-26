-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.tools.utils"
local body_transformer = require "kong.plugins.response-transformer-advanced.body_transformer"
local header_transformer = require "kong.plugins.response-transformer-advanced.header_transformer"
local feature_flag_limit_body = require "kong.plugins.response-transformer-advanced.feature_flags.limit_body"

local is_body_transform_set = header_transformer.is_body_transform_set
local is_json_body = header_transformer.is_json_body
local concat = table.concat
local kong = kong
local ngx = ngx

local ResponseTransformerHandler = {}

function ResponseTransformerHandler:init_worker()
  feature_flag_limit_body.init_worker()
end

function ResponseTransformerHandler:header_filter(conf)
  if not feature_flag_limit_body.header_filter() then
    return
  end

  header_transformer.transform_headers(conf, ngx.header, ngx.status)
end

function ResponseTransformerHandler:body_filter(conf)
  local ctx = ngx.ctx

  -- Initializes context here in case this plugin's access phase
  -- did not run - and hence `rt_body_chunks` and `rt_body_chunk_number`
  -- were not initialized
  ctx.rt_body_chunks = ctx.rt_body_chunks or {}
  ctx.rt_body_chunk_number = ctx.rt_body_chunk_number or 1

  if not feature_flag_limit_body.body_filter() then
    return
  end

  if is_body_transform_set(conf) then
    local chunk, eof = ngx.arg[1], ngx.arg[2]

    -- if eof wasn't received keep buffering
    if not eof then
      ctx.rt_body_chunks[ctx.rt_body_chunk_number] = chunk
      ctx.rt_body_chunk_number = ctx.rt_body_chunk_number + 1
      ngx.arg[1] = nil
      return
    end

    -- last piece of body is ready; do the thing
    local resp_body = concat(ctx.rt_body_chunks)

    -- raw body transformation takes precedence over
    -- json transforms
    local replaced_body = body_transformer.replace_body(conf, resp_body, ngx.status)

    if replaced_body then
      ngx.arg[1] = replaced_body
      resp_body = replaced_body
    end

    -- transform json
    if is_json_body(kong.response.get_header("Content-Type")) then
      local body, err
      local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"
      if is_gzip then
        resp_body, err = utils.inflate_gzip(resp_body)
        if err then
          kong.log.err("failed to inflate gzipped body: ", err)

          -- Empty body to prevent non-transformed (potentially sensitive)
          -- data from being passed through.
          ngx.arg[1] = nil
          ngx.status = 500
          return
        end
      end

      body, err = body_transformer.transform_json_body(conf, resp_body, ngx.status)
      if err then
        kong.log.err(err)
        return
      end

      if body then
        if is_gzip then
          body, err = utils.deflate_gzip(body)
          if err then
            kong.log.err("failed to deflate gzipped body: ", err)
            return
          end
        end

        -- Only replace with JSON body if transformation was successful.
        -- Otherwise, leave original or replaced_body (above) in place.
        ngx.arg[1] = body
      end
    end
  end
end

ResponseTransformerHandler.PRIORITY = 800
ResponseTransformerHandler.VERSION = "0.4.3"

return ResponseTransformerHandler
