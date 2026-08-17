local tty = require("kong.cmd.utils.tty")

local colors

if not tty.isatty then
  colors = setmetatable({}, {__index = function() return "" end})
else
  colors = { green = '\27[32m', yellow = '\27[33m', red = '\27[31m', reset = '\27[0m' }
end

local LOG_LEVEL = ngx.NOTICE

-- Some logging helpers
local level_cfg = {
  [ngx.DEBUG] = { "debug", colors.green },
  [ngx.INFO] = { "info", "" },
  [ngx.NOTICE] = { "notice", "" },
  [ngx.WARN] = { "warn",  colors.yellow },
  [ngx.ERR] = { "error", colors.red },
  [ngx.CRIT] = { "crit", colors.red },
}

local function set_log_level(lvl)
  if not level_cfg[lvl] then
    error("Unknown log level ", lvl, 2)
  end
  LOG_LEVEL = lvl
end

local function log(lvl, namespace, ...)
  lvl = lvl or ngx.INFO
  local lvl_literal, lvl_color = unpack(level_cfg[lvl] or {"info", ""})
  if lvl <= LOG_LEVEL then
    ngx.update_time()
    local msec = ngx.now()
    print(lvl_color,
          ("%s%s %8s %s "):format(
            ngx.localtime():sub(12),
            ("%.3f"):format(msec - math.floor(msec)):sub(2),
            ("[%s]"):format(lvl_literal), namespace
          ),
          table.concat({...}, ""),
          colors.reset)
  end
end
local function new_logger(namespace)
  return setmetatable({
    debug = function(...) log(ngx.DEBUG, namespace, ...) end,
    info = function(...) log(ngx.INFO, namespace, ...) end,
    warn = function(...) log(ngx.WARN, namespace, ...) end,
    err = function(...) log(ngx.ERR, namespace, ...) end,
    crit = function(...) log(ngx.CRIT, namespace, ...) end,
    log_exec = function(...) log(ngx.DEBUG, namespace, "=> ", ...) end,
  }, {
    __call = function(self, lvl, ...) log(lvl, namespace, ...) end,
  })
end

return {
  new_logger = new_logger,
  set_log_level = set_log_level,
}