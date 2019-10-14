local rbac       = require "kong.rbac"
local Consumers = {}

local tostring     = tostring
local concat       = table.concat
local floor        = math.floor
local type         = type
local next         = next
local fmt          = string.format
local match        = string.match

local function validate_options_value(options, schema, context)
  local errors = {}

  if schema.ttl == true and options.ttl ~= nil then
    if floor(options.ttl) ~= options.ttl or
                 options.ttl < 0 or
                 options.ttl > 100000000 then
      -- a bit over three years maximum to make it more safe against
      -- integer overflow (time() + ttl)
      errors.ttl = "must be an integer between 0 and 100000000"
    end

  elseif schema.ttl ~= true and options.ttl ~= nil then
    errors.ttl = fmt("cannot be used with '%s'", schema.name)
  end

  if schema.fields.tags and options.tags ~= nil then
    if type(options.tags) ~= "table" then
      if not options.tags_cond then
        -- If options.tags is not a table and options.tags_cond is nil at the same time
        -- it means arguments.lua gets an invalid tags arg from the Admin API
        errors.tags = "invalid filter syntax"
      else
        errors.tags = "must be a table"
      end
    elseif #options.tags > 5 then
      errors.tags = "cannot query more than 5 tags"
    elseif not match(concat(options.tags), "^[%w%.%-%_~]+$") then
      errors.tags = "must only contain alphanumeric and '., -, _, ~' characters"
    elseif #options.tags > 1 and options.tags_cond ~= "and" and options.tags_cond ~= "or" then
      errors.tags_cond = "must be a either 'and' or 'or' when more than one tag is specified"
    end

  elseif schema.fields.tags == nil and options.tags ~= nil then
    errors.tags = fmt("cannot be used with '%s'", schema.name)
  end

  if next(errors) then
    return nil, errors
  end

  return true
end

function Consumers:page_by_type(db, size, offset, options)
  if options ~= nil then
    local ok, errors = validate_options_value(options, self.schema, "select")
    if not ok then
      local err_t = self.errors:invalid_options(errors)
      return nil, tostring(err_t), err_t
    end
  end

  local rows, err_t, offset = self.strategy:page_by_type(options.type,
                                                         size or 100, offset,
                                                         options)
  if err_t then
    return rows, tostring(err_t), err_t
  end

  local entities, err
  entities, err, err_t = self:rows_to_entities(rows, options)
  if not entities then
    return nil, err, err_t
  end

  if not options or not options.skip_rbac then
    entities = rbac.narrow_readable_entities(self.schema.name, entities)
  end

  return entities, nil, nil, offset
end


return Consumers
