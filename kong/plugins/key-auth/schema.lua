local function default_key_names(t)
  if not t.key_names then
    return {"apikey"}
  end
end

return {
  no_consumer = true,
  fields = {
    key_names = { required = true, type = "array", default = default_key_names },
    hide_credentials = { type = "boolean", default = false }
  }
}
