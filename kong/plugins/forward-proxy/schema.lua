local function check_port(value)
  if value < 0 or value > 2 ^ 16 then
    return false, "invalid IP port, value must be between 0 and 2^16"
  end

  if value ~= math.floor(value) then
    return false, "invalid IP port, value must be an integer"
  end

  return true
end

return {
  fields = {
    proxy_host = {
      type = "string",
      required = true,
    },
    proxy_port = {
      type = "number",
      required = true,
      func = check_port,
    },
    proxy_scheme = {
      type = "string",
      enum = {
        "http"
      },
      required = true,
      default = "http",
    },
    https_verify = {
      type = "boolean",
      required = true,
      default = false,
    },
  }
}
