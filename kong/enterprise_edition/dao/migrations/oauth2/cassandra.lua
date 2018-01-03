return {
  {
    name = "2017-07-23-100000_rbac_oauth2_resources",
    up = function(_, _, dao)
      local rbac = require "kong.rbac"
      local bxor = require("bit").bxor

      local resource, err = rbac.register_resource("oauth2", dao)
      if not resource then
        return err
      end

      for _, p in ipairs({ "read-only", "full-access" }) do
        local perm, err = dao.rbac_perms:find_all({
          name = p,
        })
        if err then
          return err
        end
        perm = perm[1]
        perm.resources = bxor(perm.resources, 2 ^ (resource.bit_pos - 1))
        local ok, err = dao.rbac_perms:update(perm, { id = perm.id })
        if not ok then
          return err
        end
      end
    end
  },
}
