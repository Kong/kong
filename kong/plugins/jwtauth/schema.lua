local function default_id_names(t)
  if not t.id_names then
    return {"id"}
  end
end

return {
  fields = {
    id_names = { required = true, type = "array", default = default_id_names },
    hide_credentials = { type = "boolean", default = false }
  }
}
