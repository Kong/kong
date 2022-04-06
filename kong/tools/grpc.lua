local lpack = require "lua_pack"
local protoc = require "protoc"
local pb = require "pb"
local pl_path = require "pl.path"
local date = require "date"

local bpack = lpack.pack
local bunpack = lpack.unpack


local grpc = {}


local function safe_set_type_hook(type, dec, enc)
  if not pcall(pb.hook, type) then
    ngx.log(ngx.DEBUG, "no type '" .. type .. "' defined")
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
function grpc.each_method(fname, f, recurse)
  local dir = pl_path.splitpath(pl_path.abspath(fname))
  local p = protoc.new()
  p:addpath("/usr/include")
  p:addpath("/usr/local/opt/protobuf/include/")
  p:addpath("/usr/local/kong/lib/")
  p:addpath("kong")
  p:addpath("kong/include")
  p:addpath("spec/fixtures/grpc")

  p.include_imports = true
  p:addpath(dir)
  p:loadfile(fname)
  set_hooks()
  local parsed = p:parsefile(fname)

  if f then

    if recurse and parsed.dependency then
      if parsed.public_dependency then
        for _, dependency_index in ipairs(parsed.public_dependency) do
          local sub = parsed.dependency[dependency_index + 1]
          grpc.each_method(sub, f, true)
        end
      end
    end

    for _, srvc in ipairs(parsed.service or {}) do
      for _, mthd in ipairs(srvc.method or {}) do
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
