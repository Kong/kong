-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils     = require "kong.tools.utils"

local fmt = string.format

local Consumers = {}


function Consumers:page_by_type(_, size, offset, options)
  options = options or {}
  options.type = options.type or 0

  size = size or options.size or 100

  local count = 1
  local MAX_ITERATIONS = 5
  local r, err, err_t, next_offset = self:page(size, offset, options)
  if err_t then
    return nil, err, err_t
  end

  local rows = {}
  for _, c in ipairs(r) do
    if c.type == options.type then
      table.insert(rows, c)
    end
  end

  while count < MAX_ITERATIONS and #rows < size and next_offset do
    r, err, err_t, next_offset = self:page(size - #rows, next_offset, options)
    if err_t then
      return nil, err, err_t
    end
    for _, c in ipairs(r) do
      if c.type == options.type then
        table.insert(rows, c)
      end
    end
    count = count + 1
  end

  return rows, nil, nil, next_offset
end

function Consumers:select_by_username_ignore_case(username)
  local function log_multiple_matches(matches)
    local match_info = {}

    for i,match in pairs(matches) do
      table.insert(match_info, fmt("%s (id: %s)", match.username, match.id))
    end
    kong.log.notice(fmt("multiple consumers match '%s' by username case-insensitively: %s", username, table.concat(match_info, ", ")))
  end

  local function upperChar(str, i)
    if i == 0 then
      return str
    end
    return str:sub(0,i-1) .. str:sub(i,i):upper() .. str:sub(i+1)
  end

  local function postgres_query()
    local qs = fmt("SELECT * FROM consumers WHERE LOWER(username) = LOWER('%s');", username)
    return kong.db.connector:query(qs)
  end

  local function permutation_query()
    local permutations = {}

    table.insert(permutations, username)

    local split_domain_char = "@"
    local local_part, domain = table.unpack(utils.split(username, split_domain_char))
    if not domain then
      split_domain_char = ""
    end

    -- gruceo.kong@kong.com
    local lower_all = table.concat({local_part:lower(), domain}, split_domain_char)
    -- GRUCEO.KONG@kong.com
    local upper_all = table.concat({local_part:upper(), domain}, split_domain_char)
    -- Gruceo.kong@kong.com
    local upper_first_lower_rest = table.concat({upperChar(local_part:lower(), 1), domain}, split_domain_char)
    local upper_first_keep_rest = table.concat({upperChar(local_part, 1), domain}, split_domain_char)

    if username ~= lower_all then
      table.insert(permutations, lower_all)
    end

    if username ~= upper_all then
      table.insert(permutations, upper_all)
    end

    if username ~= upper_first_keep_rest then
      table.insert(permutations, upper_first_keep_rest)
    end

    if upper_first_keep_rest ~= upper_first_lower_rest then
      table.insert(permutations, upper_first_lower_rest)
    end

    -- make variants with each subpart capitalized (split by the following chars)
    -- Gruceo.Kong@kong.com
    local split_chars = {".", "-", "_"}
    for i,char in pairs(split_chars) do
      local local_subparts = utils.split(local_part, char)
      if #local_subparts > 1 then
        local capitalized_subparts = {}
        for j,subpart in pairs(local_subparts) do
          table.insert(capitalized_subparts, upperChar(subpart, 1))
        end
        table.insert(permutations, table.concat({table.concat(capitalized_subparts, char), domain}, split_domain_char))
      end
    end

    local consumers = {}
    local consumer, err
    for _,permutation in pairs(permutations) do
      consumer, err = kong.db.consumers:select_by_username(permutation)
      if consumer then
        table.insert(consumers, consumer)
      end
    end

    table.sort(consumers, function(a,b)
      return a.created_at < b.created_at
    end)

    return consumers, err
  end

  local consumers, err

  if kong.db.strategy == "postgres" then
    consumers, err = postgres_query()
  else
    consumers, err = permutation_query()
  end

  if err then
    return nil, err
  end

  if #consumers > 1 then
    log_multiple_matches(consumers)
  end

  return consumers[1], nil
end


return Consumers
