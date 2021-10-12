package.loaded.lua_pack = nil   -- BUG: why?
require "lua_pack"
local protoc = require "protoc"
local pb = require "pb"
local pl_path = require "pl.path"
local date = require "date"

local bpack=string.pack         -- luacheck: ignore string
local bunpack=string.unpack     -- luacheck: ignore string


local grpc = {}


local function safe_set_type_hook(type, dec, enc)
  if not pcall(pb.hook, type) then
    ngx.log(ngx.NOTICE, "no type '" .. type .. "' defined")
    return
  end

  if not pb.hook(type) then
    pb.hook(type, dec)
  end

  if not pb.encode_hook(type) then
    pb.encode_hook(type, enc)
  end
end

local function set_hooks()
  pb.option("enable_hooks")
  local epoch = date.epoch()

  safe_set_type_hook(
    ".google.protobuf.Timestamp",
    function (t)
      if type(t) ~= "table" then
        error(string.format("expected table, got (%s)%q", type(t), tostring(t)))
      end

      return date(t.seconds):fmt("${iso}")
    end,
    function (t)
      if type(t) ~= "string" then
        error (string.format("expected time string, got (%s)%q", type(t), tostring(t)))
      end

      local ds = date(t) - epoch
      return {
        seconds = ds:spanseconds(),
        nanos = ds:getticks() * 1000,
      }
    end)
end

--- loads a .proto file optionally applies a function on each defined method.
function grpc.each_method(fname, f)

  local dir, name = pl_path.splitpath(pl_path.abspath(fname))
  local p = protoc.new()
  p:addpath("/usr/include")
  p:addpath("/usr/local/opt/protobuf/include/")
  p:addpath("/usr/local/kong/lib/")
  p:addpath("kong")

  p.include_imports = true
  p:addpath(dir)
  p:loadfile(name)
  set_hooks()
  local parsed = p:parsefile(name)

  if f then
    for _, srvc in ipairs(parsed.service) do
      for _, mthd in ipairs(srvc.method) do
        f(parsed, srvc, mthd)
      end
    end
  end

  return parsed
end


--- wraps a binary payload into a grpc stream frame.
function grpc.frame(ftype, msg)
  return bpack("C>I", ftype, #msg) .. msg
end

--- unwraps one frame from a grpc stream.
--- If success, returns `content, rest`.
--- If heading frame isn't complete, returns `nil, body`,
--- try again with more data.
function grpc.unframe(body)
  if not body or #body <= 5 then
    return nil, body
  end

  local pos, ftype, sz = bunpack(body, "C>I")       -- luacheck: ignore ftype
  local frame_end = pos + sz - 1
  if frame_end > #body then
    return nil, body
  end

  return body:sub(pos, frame_end), body:sub(frame_end + 1)
end



return grpc
