local cjson         = require "cjson"
local cjson_safe    = require "cjson.safe"
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local fmt           = string.format


local Consumers = {}

local sql_templates = {
  page_by_type_first = [[
  SELECT id, username, custom_id, created_at
    FROM consumers
    WHERE type = %s
    ORDER BY id
    LIMIT %s;]],
  page_by_type_next  = [[
  SELECT id, username, custom_id, created_at
    FROM consumers
    WHERE id >= %s AND type = %s
    ORDER BY id
    LIMIT %s;]],
}

local function page(self, size, token, options, type)
  local limit = size + 1
  local sql
  local args
  local type_literal

  if type then
    type_literal = self:escape_literal(type)
  end

  if token then
    local token_decoded = decode_base64(token)
    if not token_decoded then
      return nil, self.errors:invalid_offset(token, "bad base64 encoding")
    end

    token_decoded = cjson_safe.decode(token_decoded)
    if not token_decoded then
      return nil, self.errors:invalid_offset(token, "bad json encoding")
    end

    local id_delimiter = self:escape_literal(token_decoded)

    if type then
      sql = sql_templates.page_by_type_next
      args = { id_delimiter, type_literal, limit }
    end
  else
    if type then
      sql = sql_templates.page_by_type_first
      args = { type_literal, limit  }
    end
  end

  sql = fmt(sql, unpack(args))

  local res, err = self.connector:query(sql)

  if not res then
    return nil, self.errors:database_error(err)
  end

  local offset
  if res[limit] then
    offset = cjson.encode(res[limit].id)
    offset = encode_base64(offset, true)
    res[limit] = nil
  end

  return res, nil, offset

end

function Consumers:page_by_type(type, size, token, options)
  return page(self, size, token, options, type)
end


return Consumers
