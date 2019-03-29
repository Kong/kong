local cjson      = require "cjson.safe"
local pl_path    = require "pl.path"
local log        = require "kong.cmd.utils.log"


local kong = kong
local timer_at = ngx.timer.at
local split = require('kong.tools.utils').split
local re_find = ngx.re.find
local kong_dict = ngx.shared.kong
local DAY = 24 * 3600
local WARNING_NOTICE_DAYS = 90
local ERROR_NOTICE_DAYS = 30
local LICENSE_NOTIFICATION_INTERVAL = DAY
local LICENSE_NOTIFICATION_LOCK_KEY = "events:license"

local _M = {}
local DEFAULT_KONG_LICENSE_PATH = "/etc/kong/license.json"


local function get_license_string()
  local license_data_env = os.getenv("KONG_LICENSE_DATA")
  if license_data_env then
    return license_data_env
  end

  local license_path
  if pl_path.exists(DEFAULT_KONG_LICENSE_PATH) then
    license_path = DEFAULT_KONG_LICENSE_PATH

  else
    license_path = os.getenv("KONG_LICENSE_PATH")
    if not license_path then
      ngx.log(ngx.CRIT, "KONG_LICENSE_PATH is not set")
      return nil
    end
  end

  local license_file = io.open(license_path, "r")
  if not license_file then
    ngx.log(ngx.CRIT, "could not open license file")
    return nil
  end

  local license_data = license_file:read("*a")
  if not license_data then
    ngx.log(ngx.CRIT, "could not read license file contents")
    return nil
  end

  license_file:close()

  return license_data
end


function _M.read_license_info()
  local license_data = get_license_string()
  if not license_data then
    return nil
  end

  local license, err = cjson.decode(license_data)
  if err then
    ngx.log(ngx.ERR, "could not decode license JSON: " .. err)
    return nil
  end

  return license
end


-- Hold a lock for the whole interval (exptime) to prevent multiple
-- worker processes from the  simultaneously.
-- Other workers do not need to wait until this lock is released,
-- and can ignore the event, knowing another worker is handling it.
-- We substract 1ms to the exp time to prevent a race condition
-- with the next timer event.
local function get_lock(key, exptime)
  local ok, err = kong_dict:safe_add(key, true, exptime - 0.001)
  if not ok and err ~= "exists" then
    log(ngx.WARN, "could not get lock from 'kong' shm: ", err)
  end

  return ok
end


local function log_license_state(expiration_time, now)
  local please_contact_str = "Please contact <support@konghq.com> to renew your license."
  local expiration_date = os.date("%Y-%m-%d", expiration_time)

  if expiration_time < now then
    ngx.log(ngx.CRIT, string.format("The Kong Enterprise license expired on %s. "..
                                    please_contact_str, expiration_date))
  elseif expiration_time < now + (ERROR_NOTICE_DAYS * DAY) then
    ngx.log(ngx.ERR, string.format("The Kong Enterprise license will expire on %s. " ..
                                   please_contact_str, expiration_date))
  elseif expiration_time < now + (WARNING_NOTICE_DAYS * DAY) then
    ngx.log(ngx.WARN, string.format("The Kong Enterprise license will expire on %s. " ..
                                    please_contact_str, expiration_date))
  end
end
_M.log_license_state = log_license_state


local function license_notification_handler(premature, expiration_time)
  if premature then
    return
  end

  timer_at(LICENSE_NOTIFICATION_INTERVAL,
           license_notification_handler,
           expiration_time)

  if not get_lock(LICENSE_NOTIFICATION_LOCK_KEY,
                  LICENSE_NOTIFICATION_INTERVAL) then
    return
  end

  log_license_state(expiration_time, ngx.time())
end


local function report_expired_license()
  local expiration_date = kong.license and
    kong.license.license               and
    kong.license.license.payload       and
    kong.license.license.payload.license_expiration_date

  if not expiration_date or
     not re_find(expiration_date, "^\\d{4}-\\d{2}-\\d{2}$") then
    return
  end

  local date_t = split(expiration_date, "-")
  local expiration_time = os.time({
    year = tonumber(date_t[1]),
    month = tonumber(date_t[2]),
    day = tonumber(date_t[3])
  })

  timer_at(0,
           license_notification_handler,
           expiration_time)
end
_M.report_expired_license = report_expired_license


return _M
