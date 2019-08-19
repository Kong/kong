local Tags = {}

-- Used by /tags/:tag endpoint
-- @tparam string tag_pk the tag value
-- @treturn table|nil,err,offset
function Tags:page_by_tag(tag, size, offset, options)
  local key = "tags:" .. tag .. "|list"
  return self:page_for_key(key, size, offset, options)
end

return Tags
