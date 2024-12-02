local _M = {}

function _M.from_dao(dao, options)
  return setmetatable({
    dao = dao,
    name = dao.schema.name,
    options = options,
  }, {
    __index = _M,
  })
end

function _M:next(size, offset)
  local rows, err, err_t, offset = self.dao:page(size, offset, self.options)

  if rows then
    for _, row in ipairs(rows) do
      row.__type = self.name
    end
  end

  return rows, err, offset
end

return _M
