local tab_new = require("table.new")
local concat = table.concat
local ngx_re_gmatch = ngx.re.gmatch
local ngx_re_match = ngx.re.match
local lower = string.lower
local max = math.max
local EMPTY = {}
local time = ngx.time
local parse_http_time = ngx.parse_http_time

-- Parses a HTTP header value into a table of directives
-- eg: Cache-Control: public, max-age=3600
--     => { public = true, ["max-age"] = 3600 }
-- @param h (string) the header value to parse
-- @return table a table of directives
local function parse_directive_header(h)
  if not h then
    return EMPTY
  end

  if type(h) == "table" then
    h = concat(h, ", ")
  end

  local t = {}
  local res = tab_new(3, 0)
  local iter = ngx_re_gmatch(h, "([^,]+)", "oj")

  local m = iter()
  while m do
    local _, err = ngx_re_match(m[0], [[^\s*([^=]+)(?:=(.+))?]], "oj", nil, res)
    if err then
      kong.log.err(err)
    end

    -- store the directive token as a numeric value if it looks like a number;
    -- otherwise, store the string value. for directives without token, we just
    -- set the key to true
    t[lower(res[1])] = tonumber(res[2]) or res[2] or true

    m = iter()
  end

  return t
end

-- Calculates resource Time-To-Live (TTL) based on Cache-Control headers
-- @param res_cc (table) the Cache-Control headers, as parsed by `parse_directive_header`
-- @return number the TTL in seconds
local function calculate_resource_ttl(res_cc)
  local max_age = res_cc and (res_cc["s-maxage"] or res_cc["max-age"])

  if not max_age then
    local expires = ngx.var.sent_http_expires

    if type(expires) == "table" then
      expires = expires[#expires]
    end

    local exp_time = parse_http_time(tostring(expires))
    if exp_time then
      max_age = exp_time - time()
    end
  end

  return max_age and max(max_age, 0) or 0
end

return {
  parse_directive_header = parse_directive_header,
  calculate_resource_ttl = calculate_resource_ttl,
}
