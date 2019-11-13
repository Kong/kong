local cassandra = require "cassandra"


local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64


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


local CQL_TAG =  [[
  SELECT tag, entity_name, entity_id FROM tags WHERE tag = ?
]]

local Tags = {}


-- Used by /tags/:tag endpoint
-- @tparam string tag_pk the tag value
-- @treturn table|nil,err,offset
function Tags:page_by_tag(tag, size, offset, options)
  if not size then
    size = self.connector:get_page_size(options)
  end

  local opts = new_tab(0, 2)

  if offset then
    local offset_decoded = decode_base64(offset)
    if not offset_decoded then
        return nil, self.errors:invalid_offset(offset, "bad base64 encoding")
    end

    offset = offset_decoded
  end

  local args = { cassandra.text(tag) }

  opts.page_size = size
  opts.paging_state = offset

  local rows, err = self.connector:query(CQL_TAG, args, opts, "read")
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



return Tags
