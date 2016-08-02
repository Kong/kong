local function default_key_names(t)
  if not t.key_names then
    return {"apikey"}
  end
end

return {
  no_consumer = true,
  fields = {
    key_names = { required = true, type = "array", default = default_key_names },
    -- Don't 401 someone without authentication, just don't fill out the user headers
    allow_unauthenticated = { required = false, type = "boolean", default = false },
    hide_credentials = { type = "boolean", default = false }
  }
}
