local buffer = require "string.buffer"
local zlib = require "ffi-zlib"


local inflate_gzip  = zlib.inflateGzip
local deflate_gzip  = zlib.deflateGzip


local _M = {}


-- lua-ffi-zlib allocated buffer of length +1,
-- so use 64KB - 1 instead
local GZIP_CHUNK_SIZE = 65535


local function read_input_buffer(input_buffer)
  return function(size)
    local data = input_buffer:get(size)
    return data ~= "" and data or nil
  end
end


local function write_output_buffer(output_buffer)
  return function(data)
    return output_buffer:put(data)
  end
end


local function gzip_helper(inflate_or_deflate, input)
  local input_buffer = buffer.new(0):set(input)
  local output_buffer = buffer.new()
  local ok, err = inflate_or_deflate(read_input_buffer(input_buffer),
                                     write_output_buffer(output_buffer),
                                     GZIP_CHUNK_SIZE)
  if not ok then
    return nil, err
  end

  return output_buffer:get()
end


--- Gzip compress the content of a string
-- @tparam string str the uncompressed string
-- @return gz (string) of the compressed content, or nil, err to if an error occurs
function _M.deflate_gzip(str)
  return gzip_helper(deflate_gzip, str)
end


--- Gzip decompress the content of a string
-- @tparam string gz the Gzip compressed string
-- @return str (string) of the decompressed content, or nil, err to if an error occurs
function _M.inflate_gzip(gz)
  return gzip_helper(inflate_gzip, gz)
end


return _M
