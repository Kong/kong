local kong = kong
local sub = string.sub
local split = require('kong.tools.utils').split

local metrics = {}


local function init(prometheus)
  metrics.license_errors = prometheus:counter("enterprise_license_errors",
                                              "Errors when collecting license info")
  metrics.license_signature = prometheus:gauge("enterprise_license_signature",
                                              "Last 32 bytes of the license signature in number")
  metrics.license_expiration = prometheus:gauge("enterprise_license_expiration",
                                                "Unix epoch time when the license expires, " ..
                                                "the timestamp is substracted by 24 hours "..
                                                "to avoid difference in timezone")
  metrics.license_features = prometheus:gauge("enterprise_license_features",
                                                "License features features",
                                              { "feature" })
end

local function license_date_to_unix(yyyy_mm_dd)
  local date_t = split(yyyy_mm_dd, "-")

  local ok, res = pcall(os.time, {
    year = tonumber(date_t[1]),
    month = tonumber(date_t[2]),
    day = tonumber(date_t[3])
  })
  if ok then
    return res
  end

  return nil, res
end

local function metric_data()
  if not metrics then
    kong.log.err("prometheus: plugin is not initialized, please make sure ",
                 " 'prometheus_metrics' shared dict is present in nginx template")
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if not kong.license or not kong.license.license then
    metrics.license_errors:inc()
    kong.log.err("cannot read kong.license when collecting license info")
    return
  end

  local lic = kong.license.license

  if lic.version ~= 1 then
    metrics.license_errors:inc()
    kong.log.err("enterprise license version (" .. (lic.version or "nil") .. ") unsupported")
    return
  end

  local sig = lic.signature
  if not sig then
    metrics.license_errors:inc()
    kong.log.err("cannot read license signature when collecting license info")
    return
  end
  -- last 32 bytes as an int32
  metrics.license_signature:set(tonumber("0x" .. sub(sig, #sig-33, #sig)))

  local expiration = lic.payload and lic.payload.license_expiration_date
  if not expiration then
    metrics.license_errors:inc()
    kong.log.err("cannot read license expiration when collecting license info")
    return
  end
  local tm, err = license_date_to_unix(expiration)
  if not tm then
    metrics.license_errors:inc()
    kong.log.err("cannot parse license expiration when collecting license info ", err)
    return
  end
  -- substract it by 24h so everyone one earth is happy monitoring it
  metrics.license_expiration:set(tm - 86400)


  metrics.license_features:set(kong.licensing:can("ee_plugins") and 1 or 0,
                              { "ee_plugins" })

  metrics.license_features:set(kong.licensing:can("write_admin_api") and 1 or 0,
                              { "write_admin_api" })
end


return {
  init        = init,
  metric_data = metric_data,
}
