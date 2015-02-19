local constants = require("cassandra.constants")
local encoding = require("encoding")
local decoding = require("decoding")

local function read_error(buffer)
  local error_code = constants.error_codes[decoding.read_int(buffer)]
  local error_message = decoding.read_string(buffer)
  return 'Cassandra returned error (' .. error_code .. '): "' .. error_message .. '"'
end

local function read_frame(self, tracing)
  local header, err, partial = self.sock:receive(8)
  if not header then
    return nil, string.format("Failed to read frame header from %s: %s", self.host, err)
  end
  local header_buffer = decoding.create_buffer(header)
  local version = decoding.read_raw_byte(header_buffer)
  local flags = decoding.read_raw_byte(header_buffer)
  local stream = decoding.read_raw_byte(header_buffer)
  local op_code = decoding.read_raw_byte(header_buffer)
  local length = decoding.read_int(header_buffer)
  local body, err, partial, tracing_id
  if length > 0 then
    body, err, partial = self.sock:receive(length)
    if not body then
      return nil, string.format("Failed to read frame body from %s: %s", self.host, err)
    end
  else
    body = ""
  end
  if version ~= constants.version_codes.RESPONSE then
    error("Invalid response version")
  end
  local body_buffer = decoding.create_buffer(body)
  if flags == 0x02 then -- tracing
    tracing_id = decoding.read_uuid(string.sub(body, 1, 16))
    body_buffer.pos = 17
  end
  if op_code == constants.op_codes.ERROR then
    return nil, read_error(body_buffer)
  end
  return {
    flags=flags,
    stream=stream,
    op_code=op_code,
    buffer=body_buffer,
    tracing_id=tracing_id
  }
end

local function hasbit(x, p)
  return x % (p + p) >= p
end

local function setbit(x, p)
  return hasbit(x, p) and x or x + p
end

local function parse_metadata(buffer)
  -- Flags parsing
  local flags = decoding.read_int(buffer)
  local global_tables_spec = hasbit(flags, constants.rows_flags.GLOBAL_TABLES_SPEC)
  local has_more_pages = hasbit(flags, constants.rows_flags.HAS_MORE_PAGES)
  local columns_count = decoding.read_int(buffer)

  -- Paging metadata
  local paging_state
  if has_more_pages then
    paging_state = decoding.read_bytes(buffer)
  end

  -- global_tables_spec metadata
  local global_keyspace_name, global_table_name
  if global_tables_spec then
    global_keyspace_name = decoding.read_string(buffer)
    global_table_name = decoding.read_string(buffer)
  end

  -- Columns metadata
  local columns = {}
  for j = 1, columns_count do
    local ksname = global_keyspace_name
    local tablename = global_table_name
    if not global_tables_spec then
      ksname = decoding.read_string(buffer)
      tablename = decoding.read_string(buffer)
    end
    local column_name = decoding.read_string(buffer)
    columns[#columns + 1] = {
      keyspace=ksname,
      table=tablename,
      name=column_name,
      type=decoding.read_option(buffer)
    }
  end

  return {
    columns_count=columns_count,
    columns=columns,
    has_more_pages=has_more_pages,
    paging_state=paging_state
  }
end

local function parse_rows(buffer, metadata)
  local columns = metadata.columns
  local columns_count = metadata.columns_count
  local rows_count = decoding.read_int(buffer)
  local values = {}
  local row_mt = {
    __index = function(t, i)
    -- allows field access by position/index, not column name only
    local column = columns[i]
    if column then
      return t[column.name]
    end
    return nil
    end,
    __len = function() return columns_count end
  }
  for i = 1, rows_count do
    local row = {}
    setmetatable(row, row_mt)
    for j = 1, columns_count do
      local value = decoding.read_value(buffer, columns[j].type)
      row[columns[j].name] = value
    end
    values[#values + 1] = row
  end
  assert(buffer.pos == #(buffer.str) + 1)
  return values
end

local function query_representation(query)
  if type(query) == "string" then
    return encoding.long_string_representation(query)
  elseif query.is_batch_statement then
    return query:representation()
  else
    return encoding.short_bytes_representation(query.id)
  end
end

--
-- Protocol exposed methods
--

local _M = {}

function _M.parse_prepared_response(response)
  local buffer = response.buffer
  local kind = decoding.read_int(buffer)
  local result = {}
  if kind == constants.result_kinds.PREPARED then
    local id = decoding.read_short_bytes(buffer)
    local metadata = parse_metadata(buffer)
    local result_metadata = parse_metadata(buffer)
    assert(buffer.pos == #(buffer.str) + 1)
    result = {
      type="PREPARED",
      id=id,
      metadata=metadata,
      result_metadata=result_metadata
    }
  else
    error("Invalid result kind")
  end
  if response.tracing_id then result.tracing_id = response.tracing_id end
  return result
end

function _M.parse_response(response)
  local result
  local buffer = response.buffer
  local kind = decoding.read_int(buffer)
  if kind == constants.result_kinds.VOID then
    result = {
      type="VOID"
    }
  elseif kind == constants.result_kinds.ROWS then
    local metadata = parse_metadata(buffer)
    result = parse_rows(buffer, metadata)
    result.type = "ROWS"
    result.meta = {
      has_more_pages=metadata.has_more_pages,
      paging_state=metadata.paging_state
    }
  elseif kind == constants.result_kinds.SET_KEYSPACE then
    result = {
      type="SET_KEYSPACE",
      keyspace=decoding.read_string(buffer)
    }
  elseif kind == constants.result_kinds.SCHEMA_CHANGE then
    result = {
      type="SCHEMA_CHANGE",
      change=decoding.read_string(buffer),
      keyspace=decoding.read_string(buffer),
      table=decoding.read_string(buffer)
    }
  else
    error(string.format("Invalid result kind: %x", kind))
  end

  if response.tracing_id then
    result.tracing_id = response.tracing_id
  end
  return result
end

function _M.query_op_code(query)
  if type(query) == "string" then
    return constants.op_codes.QUERY
  elseif query.is_batch_statement then
    return constants.op_codes.BATCH
  else
    return constants.op_codes.EXECUTE
  end
end

function _M.frame_body(query, args, options)
  -- Determine if query is a query, statement, or batch
  local query_repr = query_representation(query)

  -- Flags of the <query_parameters>
  local flags_repr = 0

  if args then
    flags_repr = setbit(flags_repr, constants.query_flags.VALUES)
  end

  local result_page_size = ""
  if options.page_size > 0 then
    flags_repr = setbit(flags_repr, constants.query_flags.PAGE_SIZE)
    result_page_size = encoding.int_representation(options.page_size)
  end

  local paging_state = ""
  if options.paging_state then
    flags_repr = setbit(flags_repr, constants.query_flags.PAGING_STATE)
    paging_state = encoding.bytes_representation(options.paging_state)
  end

  -- <query_parameters>: <consistency><flags>[<n><value_i><...>][<result_page_size>][<paging_state>]
  local query_parameters = encoding.short_representation(options.consistency_level) ..
    string.char(flags_repr) .. encoding.values_representation(args) ..
    result_page_size .. paging_state

  -- frame body: <query><query_parameters>
  return query_repr .. query_parameters
end

function _M.send_frame_and_get_response(self, op_code, body, tracing)
  local version = string.char(constants.version_codes.REQUEST)
  local flags = tracing and '\002' or '\000'
  local stream_id = '\000'
  local length = encoding.int_representation(#body)
  local frame = version .. flags .. stream_id .. string.char(op_code) .. length .. body

  local bytes, err = self.sock:send(frame)
  if not bytes then
    return nil, string.format("Failed to read frame header from %s: %s", self.host, err)
  end
  return read_frame(self)
end

return _M
