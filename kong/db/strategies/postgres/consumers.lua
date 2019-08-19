local cjson         = require "cjson"
local cjson_safe    = require "cjson.safe"
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local fmt           = string.format
local workspaces = require "kong.workspaces"
local re_sub = ngx.re.sub


local Consumers = {}

local sql_templates = {
  page_by_type = [[
  SELECT id, username, custom_id, tags, extract('epoch' from created_at at time zone 'UTC') as created_at
    FROM consumers
    WHERE type = %s
    ORDER BY id
    LIMIT %s;]],
}


function Consumers:page_by_type(type, size, token, options)
  local limit = size + 1
  local type_literal = self:escape_literal(type)
  local ws_list = workspaces.ws_scope_as_list(self.schema.name)
  local sql = sql_templates.page_by_type

  -- support next page
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
    sql = re_sub(sql, "\\bWHERE\\b", "WHERE id >= ".. id_delimiter .. " AND ", "o")
  end


  -- maybe add workspaces to the query
  if ws_list then
    local joined_consumers = [[
    FROM workspace_entities ws_e INNER JOIN consumers c
    ON ( unique_field_name = 'id' AND ws_e.workspace_id in ( %s ) and ws_e.entity_id = c.id::varchar )
]]
    sql = re_sub(sql, "\\bFROM consumers\\b", fmt(joined_consumers, ws_list), "o")
  end

  -- maybe add tags to the query
  local tags = options.tags
  if tags and options.tags_cond == "or" then
    sql = re_sub(sql, "\\bWHERE\\b", "WHERE tags && " .. self:escape_literal(tags, "tags") .. " AND ", "o")
  elseif tags then -- "and" is the default
    sql = re_sub(sql, "\\bWHERE\\b", "WHERE tags @> ".. self:escape_literal(tags, "tags") .. " AND " , "o")
  end

  sql = fmt(sql, type_literal, limit)
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


return Consumers
