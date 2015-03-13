local function check_tcp(v, t)
  local inspect = require "inspect"
  print(inspect(v))
  print(inspect(t))
  if t and t.type == "tcp" and v == nil then
    return false, "This property is required for the \"tcp\" type"
  end
  return true
end

return {
  type = { required = true, enum = { "tcp", "nginx_log" }},
  host = { func = check_tcp },
  port = { func = check_tcp },
  timeout = { func = check_tcp },
  keepalive = { func = check_tcp }
}
