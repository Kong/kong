local Tags = {}


-- Used by /tags/:tag endpoint
-- @tparam string tag_pk the tag value
-- @treturn table|nil,err,offset
function Tags:page_by_tag(tag, size, offset, options)
  options.tags = { tag, }
  return self:page_for_tags(size, offset, options)
end


-- Used by /tags endpoint
function Tags:page(size, offset, options)
  return self:page_for_tags(size, offset, options)
end


return Tags
