local function check_name(name)
  if name then
    local m, err = ngx.re.match(name, "[^\\w.\\-_~]")
    if err then
      ngx.log(ngx.ERR, err)
      return

    elseif m then
      return false, "name must only contain alphanumeric and '., -, _, ~' characters"
    end
  end

  return true
end


return {
  table = "workspaces",
  primary_key = { "id" },
  cache_key = { "name" },
  workspaceable = true,
  fields = {
    id = {
      type = "id",
      dao_insert_value = true,
      required = true,
    },
    name = {
      type = "string",
      required = true,
      unique = true,
      func = check_name
    },
    comment = {
      type = "string",
    },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
    meta = {
      type = "table",
      default = {},
    },
  },
}
