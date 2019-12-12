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
