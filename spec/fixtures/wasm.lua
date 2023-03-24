local _M = {}

local pl_utils = require "pl.utils"
local pl_dir = require "pl.dir"
local pl_path = require "pl.path"

local join = pl_path.join
local execute = pl_utils.executeex
local abspath = pl_path.abspath
local basename = pl_path.basename
local dirs = pl_dir.getdirectories
local isfile = pl_path.isfile
local fmt = string.format

_M.ROOT_PATH = "spec/fixtures/proxy_wasm_filters"
_M.TARGET_PATH = _M.ROOT_PATH .. "/target/wasm32-wasi/debug"

_M.CARGO_BUILD = table.concat({
  "cargo", "build",
    "--manifest-path", _M.ROOT_PATH .. "/Cargo.toml",
    "--workspace",
    "--lib ",
    "--target wasm32-wasi"
}, " ")

_M.MODULES = {}
_M.MODULE_NAMES = {}

do
  for _, dir in ipairs(dirs(_M.ROOT_PATH)) do
    if isfile(join(dir, "Cargo.toml")) then
      local name = dir:gsub("/+$", "")
                      :gsub(".*/", "")

      local mod = {
        name = name,
        path = abspath(join(_M.TARGET_PATH, name .. ".wasm")),
      }

      table.insert(_M.MODULES, mod)
      _M.MODULES[name] = mod

      table.insert(_M.MODULE_NAMES, name)
      _M.MODULE_NAMES[name] = name
    end
  end
end

function _M.build()
  assert(execute(_M.CARGO_BUILD))
end

function _M.link(dir)
  assert(pl_dir.makepath(dir))
  for _, mod in ipairs(_M.MODULES) do
    local target = mod.path
    local link = join(dir, basename(mod.path))
    assert(execute(fmt("ln -sf %q %q", target, link)))
  end
end

function _M.prepare(prefix, filter_path)
  prefix = prefix or "servroot"
  filter_path = filter_path or "proxy_wasm_filters"
  _M.build()
  _M.link(join(prefix, filter_path))
end


return _M
