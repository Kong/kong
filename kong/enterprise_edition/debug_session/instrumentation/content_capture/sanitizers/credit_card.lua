-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local buffer = require "string.buffer"

local re_find = ngx.re.find
local re_gsub = ngx.re.gsub
local rep = string.rep

local IGNORED_CHARS = "\\n -"
-- cards numbers that can be validated with Luhn algorithm have a length
-- between 12 and 19 digits (https://en.wikipedia.org/wiki/Payment_card_number)
-- trying to use a more complex regex here can lead to missing newly introduced
-- formats, so we match digit sequences only based on length and apply Luhn to
-- validate them (and avoid false positives).
local NUMBER_CANDIDATE_REGEX = "(\\d[" .. IGNORED_CHARS .. "]*){11,18}\\d"


-- writes text from source to buf. If source is not provided (redact mode)
-- it writes `*` characters
local function write_to_buffer(buf, source, from, to)
  local txt = source and source:sub(from, to)
              or rep("*", to - from + 1)

  buf:put(txt)
  return to + 1
end


local function extract_candidate(text, from, to)
  local candidate = text:sub(from, to)
    -- remove ignored characters from candidate
  return re_gsub(candidate, "[" .. IGNORED_CHARS .. "]", "", "jox")
end


local _M = {}


function _M.sanitize(text)
  local from, to, err = re_find(text, NUMBER_CANDIDATE_REGEX, "jox")
  if not from then
    return text, err
  end

  local buf = buffer.new(#text)

  -- start looking for next candidate at pos = 1
  local cursor = 1
  local redacted = false

  while from do
    -- append text from cursor, until the beginning of the current match
    cursor = write_to_buffer(buf, text, cursor, from - 1)

    local candidate = extract_candidate(text, from, to)
    if _M.luhn_validate(candidate) then
      redacted = true
      cursor = write_to_buffer(buf, nil, cursor, to)

    else
      -- if the current match was not redacted, move ahead by 1 character
      -- the next match/candidate, part of the same sequence could be a
      -- valid number
      cursor = write_to_buffer(buf, text, cursor, cursor)
    end

    -- find next match
    from, to = re_find(text, NUMBER_CANDIDATE_REGEX, "jox", { pos = cursor })
  end

  if not redacted then
    -- take a shortcut
    buf:reset()
    return text
  end

  -- append remaining text (after last match)
  write_to_buffer(buf, text, cursor, #text)
  return buf:get()
end


-- Use Luhn algorithm to determine if the candidate
-- is a valid credit card number
-- https://en.wikipedia.org/wiki/Luhn_algorithm
function _M.luhn_validate(candidate)
  local checksum = tonumber(candidate:sub(-1))
  if not checksum then
    return false
  end

  local sum = 0
  for i = #candidate - 1, 1, -1 do
    local n = tonumber(candidate:sub(i, i))
    if not n then
      return false
    end

    local pos = #candidate - i
    local s = pos % 2 == 0 and n or n * 2

    if s > 9 then
      s = s - 9
    end
    sum = sum + s
  end

  return (10 - sum % 10) % 10 == checksum
end


return _M
