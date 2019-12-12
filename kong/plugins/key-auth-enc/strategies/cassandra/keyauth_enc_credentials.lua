local fmt = string.format


local _M = {}

-- DO NOT USE this strategy in production. For testing purposes only
-- you agreed to it just by reading this comment.

function _M:insert_ident(row, ident)
  ngx.log(ngx.DEBUG, "inserting ", ident, " for ", row.id)

  local q = fmt([[UPDATE keyauth_enc_credentials SET key_ident = '%s' WHERE id = %s]],
                ident, row.id)


  return self.connector:query(q)
end


function _M:select_ids_by_ident(ident)
  local q = fmt([[SELECT id FROM keyauth_enc_credentials WHERE key_ident = '%s']],
                ident)

  return self.connector:query(q)
end


return _M
