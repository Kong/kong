local cassandra = require "cassandra"
local workspaces = require "kong.workspaces"
local get_workspaces = workspaces.get_workspaces
local workspaceable  = workspaces.get_workspaceable_relations()
local workspace_entities_map = workspaces.workspace_entities_map
local utils      = require "kong.tools.utils"


local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local insert = table.insert
local ipairs = ipairs


local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec)
      return {}
    end
  end
end


local CQL_TYPE =  [[
  SELECT id, username, custom_id, created_at, tags
  FROM consumers WHERE type = ? ALLOW FILTERING
]]

local CQL_TYPE_TOKEN =  [[
  SELECT id, username, custom_id, created_at, tags
  FROM consumers WHERE type = ? and
  TOKEN(id) > TOKEN(?) LIMIT ? ALLOW FILTERING
]]


local Consumers = {}


do
  local function select_query_page(cql, primary_key, token, page_size, args)
    if token then
      local args_t = utils.deep_copy(args or {})
      insert(args_t, cassandra.uuid(token))
      insert(args_t, cassandra.int(page_size))
      return CQL_TYPE_TOKEN, args_t
    end

    return cql, args
  end


  function Consumers:page_ws(ws_scope, size, offset, cql, args)
    local table_name = self.schema.name

    local primary_key = workspaceable[table_name].primary_key
    local ws_entities_map, err = workspace_entities_map(ws_scope, table_name)
    if err then
      return nil, err
    end

    local res_rows = {}

    local token = offset
    while(true) do
      local _cql, args_t = select_query_page(cql, primary_key, token, size, args)

      local rows, err = self.connector:query(_cql, args_t or args, {}, "read")
      if not rows then
        return nil, self.errors:database_error("could not execute page query: "
          .. err)
      end

      for _, row in ipairs(rows) do
        local ws_entity = ws_entities_map[row[primary_key]]
        if ws_entity then
          row.workspace_id = ws_entity.workspace_id
          row.workspace_name = ws_entity.workspace_name
          res_rows[#res_rows+1] = self:deserialize_row(row)
          if #res_rows == size then
            return res_rows, nil, encode_base64(row[primary_key])
          end
        end
        token = row[primary_key]
      end

      if #rows == 0 or #rows < size then
        break
      end
    end

    return res_rows
  end
end


function Consumers:page_by_type(type, size, offset, options)
  local opts = new_tab(0, 2)

  if offset then
    local offset_decoded = decode_base64(offset)
    if not offset_decoded then
        return nil, self.errors:invalid_offset(offset, "bad base64 encoding")
    end

    offset = offset_decoded
  end

  local args = { cassandra.int(type) }

  local ws_scope = get_workspaces()
  if #ws_scope > 0 and workspaceable[self.schema.name]  then
    return self:page_ws(ws_scope, size, offset, CQL_TYPE, args)
  end

  opts.page_size = size
  opts.paging_state = offset

  local rows, err = self.connector:query(CQL_TYPE, args, opts, "read")
  if not rows then
    if err:match("Invalid value for the paging state") then
      return nil, self.errors:invalid_offset(offset, err)
    end
    return nil, self.errors:database_error("could not execute page query: "
                                            .. err)
  end

  local next_offset
  if rows.meta and rows.meta.paging_state then
    next_offset = encode_base64(rows.meta.paging_state)
  end

  rows.meta = nil
  rows.type = nil

  for i = 1, #rows do
    rows[i] = self:deserialize_row(rows[i])
  end

  return rows, nil, next_offset

end


return Consumers
