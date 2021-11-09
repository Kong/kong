-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt = string.format


local _M = {}


function _M:insert_ident(row, ident)
  ngx.log(ngx.DEBUG, "inserting ", ident, " for ", row.id)

  local q = fmt([[UPDATE keyauth_enc_credentials SET key_ident = %s WHERE id = %s]],
                self:escape_literal(ident), self:escape_literal(row.id))


  return self.connector:query(q)
end


function _M:select_ids_by_ident(ident)
  local q = fmt([[SELECT id FROM keyauth_enc_credentials WHERE key_ident = %s]],
                self:escape_literal(ident))

  return self.connector:query(q)
end


return _M
