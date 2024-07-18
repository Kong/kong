-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ffi = require "ffi"

-- Converts a given vector into a byte string.
--
-- It is currently required by Redis that vectors sent in with FT.SEARCH need
-- to be in a byte string format. We have to use their commands interface
-- directly (since Lua client support for Redis is limited at the time of
-- writing). They do this in their Python client by storing the vector as a
-- numpy array with float32 precision and then converting it to a byte string,
-- e.g.:
--
--   vector = [0.1, 0.2, 0.3]
--   array = numpy.array(vector, dtype=numpy.float32)
--   bytes = array.tobytes()
--
-- This function produces equivalent output, and is a bit of a hack. Ideally in
-- the future a higher level vector search API will be available in Redis so
-- we don't have to do this.
--
-- @param vector the vector to encode to bytes
-- @treturn string the byte string representation of the vector
local function convert_vector_to_bytes(vector)
  local float_array = ffi.new("float[?]", #vector, unpack(vector))
  return ffi.string(float_array, ffi.sizeof(float_array))
end

return {
  convert_vector_to_bytes = convert_vector_to_bytes,
}