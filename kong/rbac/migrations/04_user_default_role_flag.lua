return {
  up = function(_, _, dao)
    local roles, err = dao.rbac_roles:find_all()
    if err then
      return err
    end

    -- based on rbac_user_role.comment, flag the role as default.
    -- not a sure-fire approach, but the best we can do without a column.
    local search_str = "Default user role generated for"
    for _, role in ipairs(roles) do
      if role.comment and role.comment:sub(1, #search_str) == search_str then
        local _, err = dao.rbac_roles:update(
            { is_default = true, },
            { id = role.id, })
        if err then
          return err
        end
      end
    end
  end
}
