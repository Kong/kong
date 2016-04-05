local BIN_PATH = "bin/kong"
local TEST_CONF_PATH = "spec/kong_tests.conf"

local conf_loader = require "kong.conf_loader"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_dir = require "pl.dir"

---------------
-- Conf and DAO
---------------
local conf = assert(conf_loader(TEST_CONF_PATH))

--local DAOFactory = require "kong.dao.factory"
--local dao = DAOFactory(conf, conf.plugins)
-- make sure migrations are up-to-date
--assert(dao:run_migrations())

--------------------
-- Custom assertions
--------------------
local say = require "say"
local luassert = require "luassert.assert"

local function fail(state, args)
  args[1] = table.concat(args, " ")
  return false
end
say:set("assertion.fail.negative", "%s")
luassert:register("assertion", "fail", fail,
                  "assertion.fail.negative",
                  "assertion.fail.negative")

local function res_status(state, args)
  local expected, res = unpack(args)
  if expected ~= res.status then
    table.insert(args, 1, res:read_body())
    table.insert(args, 1, res.status)
    table.insert(args, 1, expected)
    return false
  end
  return true, {res:read_body()}
end
say:set("assertion.res_status.negative", [[
Invalid response status code.
Status expected:
%s
Status received:
%s
Body:
%s
]])
luassert:register("assertion", "res_status", res_status,
                  "assertion.res_status.negative")

----------------
-- Shell helpers
----------------
local function exec(...)
  local ok, _, stdout, stderr = pl_utils.executeex(...)
  return ok, stderr, stdout
end

local function kong_exec(args, prefix)
  args = args or ""
  prefix = prefix or conf.prefix

  return exec(BIN_PATH.." "..args.." --prefix "..prefix)
end

----------
-- Exposed
----------
return {
  -- Penlight
  dir = pl_dir,
  path = pl_path,
  file = pl_file,
  execute = pl_utils.executeex,

  -- Kong testing properties
  bin_path = BIN_PATH,
  test_conf = conf,
  test_conf_path = TEST_CONF_PATH,

  -- Kong testing helpers
  kong_exec = kong_exec,
  prepare_prefix = function(prefix)
    prefix = prefix or conf.prefix
    pl_dir.makepath(prefix)
    kong_exec("stop", prefix)
  end,
  clean_prefix = function(prefix)
    prefix = prefix or conf.prefix
    if pl_path.exists(prefix) then
      pl_dir.rmtree(prefix)
    end
  end,
  start_kong = function(prefix)
    return kong_exec("start --conf "..TEST_CONF_PATH, prefix)
  end,
  stop_kong = function(prefix)
    return kong_exec("stop ", prefix)
  end
}
