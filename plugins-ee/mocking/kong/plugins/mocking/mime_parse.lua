-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local stringx = require "pl.stringx"
local parse_mime_type = require "kong.tools.mime_type".parse_mime_type

local tonumber = tonumber
local ipairs = ipairs
local split = stringx.split
local strip = stringx.strip

local mime_parse = {}

local function parse_media_range(range)
  local media_type, media_subtype, params = parse_mime_type(strip(range))
  local result = {
    type = media_type,
    sub_type = media_subtype,
    params = params or {},
  }
  local quality_value = tonumber(result.params.q)
  if not quality_value or quality_value < 0 or quality_value > 1 then
    result.params.q = 1
  else
    result.params.q = quality_value
  end
  return result
end

local function compute_score(mime_type, parsed_results)
  local best_score = 0
  local target = parse_media_range(mime_type)

  for _, result in ipairs(parsed_results) do
    if (target.type == result.type or target.type == "*" or result.type == "*")
      and (target.sub_type == result.sub_type or target.sub_type == "*" or result.sub_type == "*") then
      local quality_value = result.params.q
      local score = target.type == result.type and 100 or 0
      score = score + (target.sub_type == result.sub_type and 10 or 0)
      score = score + quality_value
      if score > best_score then
        best_score = score
      end
    end
  end

  return best_score
end

mime_parse.best_match = function(supported_types, header)
  local parse_range_list = {}
  local ranges = split(header, ",")
  for i, range in ipairs(ranges) do
    parse_range_list[i] = parse_media_range(range)
  end

  local best_match_score = 0
  local best_match_type
  for _, type in ipairs(supported_types) do
    local score = compute_score(type, parse_range_list)
    if score > best_match_score then
      best_match_type = type
      best_match_score = score
    end
  end

  if best_match_score == 0 then
    return ""
  end
  return best_match_type
end

-- only for test
mime_parse._compute_score = compute_score
mime_parse._parse_media_range = parse_media_range

return mime_parse
