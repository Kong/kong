-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local gzip = require "kong.tools.gzip"
local body_transformer = require "kong.plugins.response-transformer-advanced.body_transformer"
local header_transformer = require "kong.plugins.response-transformer-advanced.header_transformer"
local feature_flag_limit_body = require "kong.plugins.response-transformer-advanced.feature_flags.limit_body"
local meta = require "kong.meta"
local transform_utils = require "kong.plugins.response-transformer-advanced.transform_utils"

local is_body_transform_set = header_transformer.is_body_transform_set
local is_json_body = header_transformer.is_json_body
local skip_transform = transform_utils.skip_transform
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
  if not feature_flag_limit_body.body_filter() then
    return
  end

  if is_body_transform_set(conf) then
    local resp_body
    if not skip_transform(ngx.status, conf.replace.if_status) and conf.replace.body then
      -- follow origin behavior, if no body, do not transform
      if not kong.response.get_raw_body() then
        return
      end

      -- raw body transformation takes precedence over
      -- json transforms
      kong.response.set_raw_body(conf.replace.body)
      resp_body = conf.replace.body
    end

    -- transform json
    if is_json_body(kong.response.get_header("Content-Type")) then
      local body, err
      local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"
      if is_gzip then
        resp_body = kong.response.get_raw_body()
        if not resp_body then
          return
        end

        resp_body, err = gzip.inflate_gzip(resp_body)
        if err then
          kong.log.err("failed to inflate gzipped body: ", err)

          -- Empty body to prevent non-transformed (potentially sensitive)
          -- data from being passed through.
          kong.response.set_raw_body("")
          ngx.status = 500
          return
        end
      end

      local transform_ops =  kong.table.new(0, 7)
      transform_ops = body_transformer.determine_transform_operations(conf, ngx.status, transform_ops)
      if transform_ops._need_transform then
        if not resp_body then
          resp_body = kong.response.get_raw_body()
          if not resp_body then
            kong.table.clear(transform_ops)
            return
          end
        end

        body, err = body_transformer.transform_json_body(conf, resp_body, transform_ops)
        kong.table.clear(transform_ops)
        if err then
          kong.log.err(err)
          return
        end

        if body then
          if is_gzip then
            body, err = gzip.deflate_gzip(body)
            if err then
              kong.log.err("failed to deflate gzipped body: ", err)
              return
            end
          end

          -- Only replace with JSON body if transformation was successful.
          -- Otherwise, leave original or replaced_body (above) in place.
          kong.response.set_raw_body(body)
        end
      end
      kong.table.clear(transform_ops)
    end
  end
end

ResponseTransformerHandler.PRIORITY = 800
ResponseTransformerHandler.VERSION = meta.core_version

return ResponseTransformerHandler
