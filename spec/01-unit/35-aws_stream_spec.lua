local aws_stream = require("kong.tools.aws_stream")


describe("aws stream", function()
  it("reject incomplete message", function()
    local frame = "\0\0\0\44" ..  -- total length
      "\0\0\0\0" ..  -- headers length (0)
      "\0\0\0\0" ..  -- crc
      ("1234567"):rep(4)          -- payload, 4 bytes are missing
    local stream, err = aws_stream:new(frame)
    assert.is_nil(err)
    assert.equal(40, stream:bytes())
    local msg, err = stream:next_message()
    assert.is_nil(msg)
    assert.equal(err, "not enough bytes in buffer for a complete message")

    local frame = "\0\0\0\40" ..  -- total length
      "\0\0\0\0" ..  -- headers length (0)
      "\0\0\0\0" ..  -- crc
      ("1234567"):rep(4) ..      -- payload
      "\0\1" -- incomplete length for the next message
    local stream, err = aws_stream:new(frame)
    assert.is_nil(err)
    stream:next_message()
    local msg, err = stream:next_message()
    assert.is_nil(msg)
    assert.equal(err, "not enough bytes in buffer for a complete message")
  end)

  it("reject out of bound", function()
    -- test for low-level api
    local frame = "\0\0\0\40" ..  -- total length
      "\0\0\0\0" ..  -- headers length (0)
      "\0\0\0\0" ..  -- crc
      ("1234567"):rep(4)          -- payload
    local stream, err = aws_stream:new(frame)
    assert.is_nil(err)
    local bytes, err = stream:next_bytes(44)  -- request more bytes than available
    assert.is_nil(bytes)
    assert.equal(err, "not enough bytes in buffer when trying to read 44 bytes, only 40 bytes available")

    local stream = aws_stream:new(frame)
    local bytes = stream:next_bytes(40) -- request exact number of bytes
    assert.is_not_nil(bytes)
    bytes, err = stream:next_bytes(1)  -- request one more byte
    assert.is_nil(bytes)
    assert.equal(err, "not enough bytes in buffer when trying to read 1 bytes, only 0 bytes available")
  end)

  it("check completion", function()
    local frame = "\0\0\0\44" ..  -- total length
      "\0\0\0\0" ..  -- headers length (0)
      "\0\0\0\0" ..  -- crc
      ("1234567"):rep(4)          -- payload, 4 bytes are missing
    local stream = aws_stream:new(frame)
    assert.is_false(stream:has_complete_message())
    stream:add("1234")  -- add the missing bytes
    assert.is_true(stream:has_complete_message())
    local msg = stream:next_message()
    assert.same(("1234567"):rep(4), msg.body)

    local frame = "\0\0\0\40" ..  -- total length
      "\0\0\0\0" ..  -- headers length (0)
      "\0\0\0\0" ..  -- crc
      ("1234567"):rep(4) ..      -- payload
      "\0\0\0\40" -- incomplete length for the next message
    local stream = aws_stream:new(frame)
    assert.is_true(stream:has_complete_message())
    stream:next_message()
    assert.is_false(stream:has_complete_message())
    local remain = "\0\0\0\0" ..  -- headers length (0)
      "\0\0\0\0" ..  -- crc
      ("1234567"):rep(4)      -- payload
    stream:add(remain)  -- add the missing bytes
    assert.is_true(stream:has_complete_message())
  end)
end)
