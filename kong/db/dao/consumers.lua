local Consumers = {}


function Consumers:page_by_type(db, size, offset, options)
  local rows, err_t, offset = self.strategy:page_by_type(options.type,
                                                         size or 100, offset,
                                                         options)
  if err_t then
    return rows, tostring(err_t), err_t
  end
  return rows, nil, nil, offset
end


return Consumers
