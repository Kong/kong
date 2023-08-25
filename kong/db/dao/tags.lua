-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local Tags = {}

function Tags:page_by_tag(tag, size, offset, options)
  local ok, err = self.schema:validate_field(self.schema.fields.tag, tag)
  if not ok then
    local err_t = self.errors:invalid_unique('tag', err)
    return nil, tostring(err_t), err_t
  end

  local rows, err_t, offset = self.strategy:page_by_tag(tag, size, offset, options)
  if err_t then
    return rows, tostring(err_t), err_t
  end
  if type(rows) == "table" then
    setmetatable(rows, cjson.array_mt)
  end
  return rows, nil, nil, offset
end

local function noop(self, ...)
  local err_t = self.errors:schema_violation({ tags = 'does not support insert/upsert/update/delete operations' })
  return nil, tostring(err_t), err_t
end

Tags.insert = noop
Tags.delete = noop
Tags.update = noop
Tags.upsert = noop

return Tags
