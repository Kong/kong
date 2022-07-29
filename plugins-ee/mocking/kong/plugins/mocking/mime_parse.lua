-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local stringx = require "pl.stringx"

local split = stringx.split
local strip = stringx.strip

local mime_parse = {}

local function parse_mime_type(mime_type)
  local parts = split(mime_type, ";")
  local parse_result = {
    type = nil,
    sub_type = nil,
    params = {},
  }

  for i = 2, #parts do
    local p = parts[i]
    local sub_parts = split(p, "=")
    if #sub_parts == 2 then
      parse_result.params[strip(sub_parts[1])] = strip(sub_parts[2])
    end
  end

  local full_type = strip(parts[1])
  if full_type == "*" then
    full_type = "*/*"
  end
  local types = split(full_type, "/")
  if #types == 2 then
    parse_result.type = strip(types[1])
    parse_result.sub_type = strip(types[2])
  end
  return parse_result
end

local function parse_media_rage(range)
  local result = parse_mime_type(range)
  local quality_value = tonumber(result.params.q)
  if quality_value == nil or quality_value < 0 or quality_value > 1 then
    result.params.q = "1"
  end
  return result
end

local function compute_score(mime_type, parsed_results)
  local best_score = 0
  local target = parse_media_rage(mime_type)

  for _, result in ipairs(parsed_results) do
    if (target.type == result.type or target.type == "*" or result.type == "*")
      and (target.sub_type == result.sub_type or target.sub_type == "*" or result.sub_type == "*") then
      local quality_value = tonumber(result.params.q)
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
  local scored_list = {}
  local ranges = split(header, ",")
  for _, range in ipairs(ranges) do
    table.insert(parse_range_list, parse_media_rage(range))
  end

  for _, type in ipairs(supported_types) do
    local score = compute_score(type, parse_range_list)
    table.insert(scored_list, {
      mime_type = type,
      score = score
    })
  end

  table.sort(scored_list, function(o1, o2)
    return o1.score > o2.score
  end)

  local best_match = scored_list[1]
  if best_match.score == 0 then
    return ""
  end
  return best_match.mime_type
end

return mime_parse
