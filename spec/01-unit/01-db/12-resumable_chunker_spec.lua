local resumable_chunker = require("kong.db.resumable_chunker")

local function insert_dao(db, daos, name)
  local dao = {}
  table.insert(daos, dao)
  db[name] = dao
  dao.schema = { name = name }
  return dao
end

local function mock_field(db, daos, name, tbl)
  local dao = insert_dao(db, daos, name)

  local rows = {}
  for _, row in ipairs(tbl) do
    table.insert(rows, { field = row })
  end

  function dao.page(self, size, offset)
    offset = offset or 1
    local ret = {}
    for i = 1, size do
      local row = rows[offset]
      if not row then
        return ret, nil, nil, nil
      end
      ret[i] = row
      offset = offset + 1
    end
    
    return ret, nil, nil, rows[offset] and offset or nil
  end
end

local function mock_error_field(db, daos, name)
  local dao = insert_dao(db, daos, name)

  function dao.page(self, size, offset)
    return nil, "error: " .. name
  end
end

local function process_row(rows)
  for i, row in ipairs(rows) do
    rows[i] = row.field
  end
  return rows
end

describe("resumable_chunker.from_daos", function()
  it("handling empty table", function ()
    local db, daos = {}, {}
    local chunker = resumable_chunker.from_daos(daos)
    local rows, err, offset = chunker:next(1)
    assert.same({}, rows)
    assert.is_nil(err)
    assert.is_nil(offset)

    mock_field(db, daos, "field", {})
    local chunker = resumable_chunker.from_daos(daos)
    local rows, err, offset = chunker:next(1)
    assert.same({}, rows)
    assert.is_nil(err)
    assert.is_nil(offset)
  end)

  it("handling exact size", function ()
    local strategy = {}
    local db, daos = {}, {}
    mock_field(db, daos, "field", { 1, 2, 3, 4, 5 })
    local chunker = resumable_chunker.from_daos(daos)
    local rows, err, offset = chunker:next(5)
    assert.are.same({ 1, 2, 3, 4, 5 }, process_row(rows))
    assert.is_nil(err)
    assert.is_nil(offset)
  end)

  it("handling less than size", function ()
    local strategy = {}
    local db, daos = {}, {}
    mock_field(db, daos, "field", { 1, 2, 3, 4, 5 })
    local chunker = resumable_chunker.from_daos(daos)
    local rows, err, offset = chunker:next(6)
    assert.are.same({ 1, 2, 3, 4, 5 }, process_row(rows))
    assert.is_nil(err)
    assert.is_nil(offset)
  end)

  it("handling more than size", function ()
    local strategy = {}
    local db, daos = {}, {}
    mock_field(db, daos, "field", { 1, 2, 3, 4, 5 })
    local chunker = resumable_chunker.from_daos(daos)
    local rows, err, offset = chunker:next(4)
    assert.are.same({ 1, 2, 3, 4 }, process_row(rows))
    assert.is_nil(err)
    assert.truthy(offset)
    local rows, err, offset = chunker:next(4, offset)
    assert.are.same({ 5 }, process_row(rows))
    assert.is_nil(err)
    assert.is_nil(offset)
  end)

  it("handling multiple table", function ()
    local strategy = {}
    local db, daos = {}, {}
    mock_field(db, daos, "field1", { 1, 2, 3, 4, 5 })
    mock_field(db, daos, "field2", { 6, 7, 8, 9, 10 })
    local chunker = resumable_chunker.from_daos(daos)
    local rows, err, offset = chunker:next(6)
    assert.are.same({ 1, 2, 3, 4, 5, 6 }, process_row(rows))
    assert.is_nil(err)
    assert.truthy(offset)
    local rows, err, offset = chunker:next(6, offset)
    assert.are.same({ 7, 8, 9, 10 }, process_row(rows))
    assert.is_nil(err)
    assert.is_nil(offset)
  end)

  it("handling exhausted table", function ()
    local strategy = {}
    local db, daos = {}, {}
    mock_field(db, daos, "field1", { 1, 2, 3, 4, 5 })
    mock_field(db, daos, "field2", { 6, 7, 8, 9, 10 })
    local chunker = resumable_chunker.from_daos(daos)
    local rows, err, offset = chunker:next(11)
    assert.are.same({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, process_row(rows))
    assert.is_nil(err)
    assert.is_nil(offset)
  end)

  it("handling error", function ()
    local strategy = {}
    local db, daos = {}, {}
    mock_field(db, daos, "field", { 1, 2, 3, 4, 5 })
    mock_error_field(db, daos, "error")
    local chunker = resumable_chunker.from_daos(daos)
    local rows, err, offset = chunker:next(4)
    assert.are.same({ 1, 2, 3, 4 }, process_row(rows))
    assert.is_nil(err)
    assert.truthy(offset)
    local rows, err, offset = chunker:next(4, offset)
    assert.is_nil(rows)
    assert.are.same("error: error", err)
  end)

  it("resumable", function ()
    local strategy = {}
    local db, daos = {}, {}
    mock_field(db, daos, "field1", { 1, 2, 3, 4, 5 })
    mock_field(db, daos, "field2", { 6, 7, 8, 9, 10 })
    local chunker = resumable_chunker.from_daos(daos)
    local rows, err, offset = chunker:next(6)
    assert.are.same({ 1, 2, 3, 4, 5, 6 }, process_row(rows))
    assert.is_nil(err)
    assert.truthy(offset)
    local offset1 = offset
    local rows, err, offset = chunker:next(6, offset)
    assert.are.same({ 7, 8, 9, 10 }, process_row(rows))
    assert.is_nil(err)
    assert.is_nil(offset)
    local rows, err, offset = chunker:next(5)
    assert.are.same({ 1, 2, 3, 4, 5 }, process_row(rows))
    assert.is_nil(err)
    assert.truthy(offset)
    local offset2 = offset
    local rows, err, offset = chunker:next(6, offset)
    assert.are.same({ 6, 7, 8, 9, 10 }, process_row(rows))
    assert.is_nil(err)
    assert.is_nil(offset)
    local rows, err, offset = chunker:next(3, offset1)
    assert.are.same({ 7, 8, 9 }, process_row(rows))
    assert.is_nil(err)
    assert.truthy(offset)
    local rows, err, offset = chunker:next(3, offset2)
    assert.are.same({ 6, 7, 8 }, process_row(rows))
    assert.is_nil(err)
    assert.truthy(offset)
    local rows, err, offset = chunker:next(3, offset)
    assert.are.same({ 9, 10 }, process_row(rows))
    assert.is_nil(err)
    assert.is_nil(offset)
  end)
end)
