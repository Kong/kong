-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
