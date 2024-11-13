-- Module for parsing Zipkin span tags introduced by requests with a special header
-- by default the header is called Zipkin-Tags
--
-- For example, the following http request header:
--
--   Zipkin-Tags: foo=bar; baz=qux
--
-- Will add two tags to the request span in Zipkin


local split = require "kong.tools.string".split

local match = string.match

local request_tags = {}


-- note that and errors is an output value; we do this instead of
-- a return in order to be more efficient (allocate less tables)
local function parse_tags(tags_string, dest, errors)
  local items = split(tags_string, ";")
  local item

  for i = 1, #items do
    item = items[i]
    if item ~= "" then
      local name, value = match(item, "^%s*(%S+)%s*=%s*(.*%S)%s*$")
      if name then
        dest[name] = value

      else
        errors[#errors + 1] = item
      end
    end
  end
end


-- parses req_headers into extra zipkin tags
-- returns tags, err
-- note that both tags and err can be non-nil when the request could parse some tags but rejects others
-- tag can be nil when tags_header is nil. That is not an error (err will be empty)
function request_tags.parse(tags_header)
  if not tags_header then
    return nil, nil
  end

  local t = type(tags_header)
  local tags, errors = {}, {}

  -- "normal" requests are strings
  if t == "string" then
    parse_tags(tags_header, tags, errors)

  -- requests where the tags_header_name header is used more than once get an array
  --
  -- example - a request with the headers:
  --   zipkin-tags: foo=bar
  --   zipkin-tags: baz=qux
  --
  -- will get such array. We have to transform that into { foo=bar, baz=qux }
  elseif t == "table" then
    for i = 1, #tags_header do
      parse_tags(tags_header[i], tags, errors)
    end

  else
    return nil,
           string.format("unexpected tags_header type: %s (%s)",
                         tostring(tags_header), t)
  end

  if next(errors) then
    errors = "Could not parse the following Zipkin tags: " .. table.concat(errors, ", ")
  else
    errors = nil
  end

  return tags, errors
end

return request_tags
