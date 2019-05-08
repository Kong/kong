local cjson         = require "cjson"
local cjson_safe    = require "cjson.safe"
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local fmt           = string.format
local workspaces = require "kong.workspaces"
local unpack        = unpack


local Consumers = {}

local sql_templates = {
  page_by_type_first = [[
  SELECT id, username, custom_id, extract('epoch' from created_at at time zone 'UTC') as created_at
    FROM consumers
    WHERE type = %s
    ORDER BY id
    LIMIT %s;]],
  page_by_type_next  = [[
  SELECT id, username, custom_id, extract('epoch' from created_at at time zone 'UTC') as created_at
    FROM consumers
    WHERE id >= %s AND type = %s
    ORDER BY id
    LIMIT %s;]],

  page_by_type_first_ws  = [[
    SELECT id, username, custom_id, extract('epoch' from created_at at time zone 'UTC') as created_at
    FROM workspace_entities ws_e INNER JOIN consumers c
    ON ( unique_field_name = 'id' AND ws_e.workspace_id in ( %s ) and ws_e.entity_id = c.id::varchar )
    WHERE type = %s ORDER BY id LIMIT %s;
  ]],

  page_by_type_next_ws  = [[
    SELECT id, username, custom_id, extract('epoch' from created_at at time zone 'UTC') as created_at
    FROM workspace_entities ws_e INNER JOIN consumers c
    ON ( unique_field_name = 'id' AND ws_e.workspace_id in ( %s ) and ws_e.entity_id = c.id::varchar )
    WHERE id >= %s AND type = %s ORDER BY id LIMIT %s;
  ]],
}


function Consumers:page_by_type(type, size, token, options)
  local limit = size + 1
  local sql
  local args
  local ws_suffix = ""

  -- maybe validate type
  local type_literal = self:escape_literal(type)

  local ws_list = workspaces.ws_scope_as_list(self.schema.name)
  if ws_list then
    ws_suffix = "_ws"
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

    sql = sql_templates["page_by_type_next" .. ws_suffix]
    args = { id_delimiter, type_literal, limit }
  else
    sql = sql_templates["page_by_type_first" .. ws_suffix]
    args = { type_literal, limit  }
  end

  if ws_list then
    sql = fmt(sql, ws_list, unpack(args))
  else
    sql = fmt(sql, unpack(args))
  end

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
