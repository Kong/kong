local re_match = ngx.re.match

local check_regex = function(value)
  if value and (#value > 1 or value[1] ~= "*") then
    for _, origin in ipairs(value) do
      local _, err = re_match("just a string to test", origin)
      if err then
        return false, "origin '" .. origin .. "' is not a valid regex"
      end
    end
  end
  return true
end

return {
  no_consumer = true,
  fields = {
    origins = { type = "array", func = check_regex },
    headers = { type = "array" },
    exposed_headers = { type = "array" },
    methods = { type = "array", enum = { "HEAD", "GET", "POST", "PUT", "PATCH", "DELETE" } },
    max_age = { type = "number" },
    credentials = { type = "boolean", default = false },
    preflight_continue = { type = "boolean", default = false }
  }
}
