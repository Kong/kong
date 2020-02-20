local connector = require "kong.db.strategies.connector"


local tostring = tostring


local iteration = {}


function iteration.failed(err, err_t)
  local failed = false
  return function()
    if failed then
      return nil
    end
    failed = true
    return false, err, err_t
  end
end


local function page_iterator(pager, size, options)
  local page = 1

  if not size then
    size = connector:get_page_size(options)
  end

  local i, rows, err, offset = 0, pager(size, nil, options)

  return function()
    if not rows then
      return nil, err
    end

    i = i + 1

    local row = rows[i]
    if row then
      return row, nil, page
    end

    if i > size and offset then
      i, rows, err, offset = 1, pager(size, offset, options)
      if not rows then
        return nil, err
      end

      page = page + 1

      return rows[i], nil, page
    end

    return nil
  end
end


function iteration.by_row(self, pager, size, options)
  local next_row = page_iterator(pager, size, options)

  local failed = false -- avoid infinite loop if error is not caught
  return function()
    local err_t
    if failed then
      return nil
    end
    local row, err, page = next_row()
    if not row then
      if err then
        failed = true
        if type(err) == "table" then
          return false, tostring(err), err
        end

        err_t = self.errors:database_error(err)
        return false, tostring(err_t), err_t
      end

      return nil
    end

    if not self.row_to_entity then
      return row, nil, page
    end

    row, err, err_t = self:row_to_entity(row)
    if not row then
      failed = true
      return false, err, err_t
    end

    return row, nil, page
  end
end


return iteration
