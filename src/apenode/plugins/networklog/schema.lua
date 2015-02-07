local function check_tcp(v, t)
  if t and t == "tcp" and not v then
    return false, "This property is required for the \"tcp\" type"
  end
  return true
end

local NetworkLogHandler = BasePlugin:extend()

return {
  type = { type = "string", required = true, enum = { "tcp", "nginx_log" } },
  host = { type = "string", func = check_tcp },
  port = { type = "number", func = check_tcp },
  timeout = { type = "number", func = check_tcp },
  keepalive = { type = "number", func = check_tcp }
}