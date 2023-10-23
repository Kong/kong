local lpack = require "lua_pack"
local pbc = require "protoc" -- protocol buffer compiler, similar to `pb` standing for `protocol buffers`
local pl_path = require "pl.path"

local bpack = lpack.pack
local bunpack = lpack.unpack
local ipairs = ipairs

local _M = {}
local _MT = { __index = _M }

--- Constructor
function _M.new()
  local self = setmetatable( {
    protoc = pbc.new()
  }, _MT )
  
  self.protoc.include_imports = true

  -- include default paths for proto lookup
  self.protoc:addpath( "/usr/include" )
  self.protoc:addpath( "/usr/local/opt/protobuf/include/" )
  self.protoc:addpath( "/usr/local/kong/lib/" )
  self.protoc:addpath( "kong" )
  self.protoc:addpath( "kong/include" )
 
  return self
end

--- Executes function for every method in file
-- @param file File descriptor
-- @param f Functiont to execute
local function for_each_method( file, f )
  for _, service in ipairs( file.service or {} ) do
    for _, method in ipairs( service.method or {} ) do
      f( file, service, method )
    end
  end
end

--- Executes function for every field in file
-- Handles also nested types
-- @param file File descriptor
-- @param f Functiont to execute
local function for_each_field( file, f )
  local function parse_message( msg )
    for _, field in pairs( msg.field or {} ) do
      f( file, msg, field )
    end

    -- traverse nested types
    for _, nm in pairs( msg.nested_type or {} ) do
      nm.full_name = msg.full_name .. "." .. nm.name
      parse_message( nm )
    end
  end

  for _, msg in pairs( file.message_type or {} ) do
    msg.full_name = "." .. file.package .. "." .. msg.name
    parse_message( msg )
  end
end

--- Add path to search for parsed proto files
-- @param path Path to add
function _M:add_path( path ) 
  self.protoc:addpath( path )
end

--- Traverse proto file and call hooks if possible
-- File is processed recursively according to `protoc.include_import` settings
-- Hooks are optional
-- @param filename Filename to parse
-- @param method_hook Function to be called for each method
-- @param field_hook Function to be called for each field (also in nested messages)
function _M:traverse_proto_file( filename, method_hook, field_hook )
  local p = self.protoc

  -- Add directory containing parsed file to paths
  local dir = pl_path.splitpath( pl_path.abspath( filename ))
  p:addpath( dir ) 

  p:loadfile( filename )

  local file = p.loaded[ filename ] or {}
  
  -- imports first approach
  if p.include_imports then
    for _, i in ipairs( file.public_dependency or {} ) do
      self:traverse_proto_file( file.dependency[ i + 1 ], method_hook, field_hook )
    end
  end

  if method_hook then
    for_each_method( file, method_hook )
  end
  
  if field_hook then
    for_each_field( file, field_hook )
  end
end

--- Wraps a binary payload into a grpc stream frame.
function _M.frame(ftype, msg)
  -- byte 0: frame type
  -- byte 1-4: frame size in big endian (could be zero)
  -- byte 5-: frame content
  return bpack("C>I", ftype, #msg) .. msg
end

--- Unwraps one frame from a grpc stream.
-- If success, returns `content, rest`.
-- If heading frame isn't complete, returns `nil, body`,
-- try again with more data.
function _M.unframe(body)
  -- must be at least 5 bytes(frame header)
  if not body or #body < 5 then
    return nil, body
  end

  local pos, ftype, sz = bunpack(body, "C>I") -- luacheck: ignore ftype
  local frame_end = pos + sz - 1
  if frame_end > #body then
    return nil, body
  end

  return body:sub(pos, frame_end), body:sub(frame_end + 1)
end

--- Opens file named `fname`, if exists. 
-- Looks up every path registered to `protoc`.
-- @param fname file name
-- @return file handle or nil if there was no file found
function _M:open_proto_file( fname )
  for _, path in ipairs( self.protoc.paths ) do
    local fn = path ~= "" and path .. "/" .. fname or fname
    local fh, _ = io.open(fn)
    if fh then
      return fh
    end
  end
  return nil
end

return _M
