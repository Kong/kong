local function check_tcp(v, t)
  if t and t == "tcp" and not v then
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
