-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local log        = require "kong.plugins.jwt-signer.log"
local cache      = require "kong.plugins.jwt-signer.cache"
local uuid       = require "kong.tools.uuid"
local timer_at   = ngx.timer.at
local min        = math.min
local tb_insert  = table.insert

local _M = {}

local timers = {
  -- name = {
  -- id,
  -- period,
  -- username,
  -- password,
  -- certificate,
  -- retries,
  -- }
}

local mutex_opts = {
  no_wait = true,
}


local function rotate_handler(premature, name, timer_id)
  if premature then
    return
  end

  local timer = timers[name]

  if not timer or timer.id ~= timer_id then
    log("stale timer of auto-rotating jwks for ", name, ", timer_id: ", timer_id)
    return
  end

  log("start auto-rotating jwks for ", name)

  local ok, err
  local cb_err
  -- prevent multiple nodes from rotating the same key set simultaneously
  ok, err = kong.db:cluster_mutex("jwt_signer_rotate:" .. name, mutex_opts, function()
    local row, err2 = cache.get_keys(name)
    if err2 then
      cb_err = "failed to get jwks: " .. err2
      return nil, cb_err
    end

    local time_since_last_update = cache.is_rotated_recently(row, timer.period)
    if time_since_last_update then
      log.notice("jwks for ", name, " were rotated ",
                 time_since_last_update, "s ago (skipping)")
      return true
    end

    local opts = {
      client_username     = timer.username,
      client_password     = timer.password,
      client_certificate  = timer.certificate,
    }

    local ok2
    ok2, err2 = cache.rotate_keys(name, row, true, true, true, opts)
    if not ok2 then
      cb_err = "failed to rotate jwks: " .. err2
      return nil, cb_err
    end

    return true
  end)

  local delay = timer.period
  if ok == false then
    log.notice("another node is already rotating jwks for ", name, " (skipping)")
    timer.retries = 0

  elseif ok == nil or cb_err then
    log.err(err or cb_err)

    -- limit the maximum retries to 5
    if timer.retries < 5 then
      -- set a shorter delay on failure (exponential backoff)
      delay = 2 ^ timer.retries * 30    -- initial delay: 30s
      delay = min(delay, timer.period)
      timer.retries = timer.retries + 1

    else
      timer.retries = 0
    end

  else
    log("finish auto-rotating jwks for ", name)
    timer.retries = 0
  end

  log("the next rotation for ", name, " will be after ", delay, "s")

  local _
  _, err = timer_at(delay, rotate_handler, name, timer_id)
  if err then
    log.err("failed to create a rotate timer for ", name, ": ", err)
    return
  end
end


local function create_timer(name, timer)
  local id = uuid.uuid()

  log("creating timer of auto-rotating jwks for ", name, ", timer_id: ", id)
  local ok, err = timer_at(0, rotate_handler, name, id)
  if not ok then
    log.err("failed to create a rotate timer for ", name, ": ", err)
    return
  end

  timers[name] = {
    id            = id,
    period        = timer.period,
    username      = timer.username,
    password      = timer.password,
    certificate   = timer.certificate,
    retries       = 0,
  }
end


local function update_timer(name, timer)
  local id = timers[name].id
  log("updating timer of auto-rotating jwks for ", name, ", timer_id: ", id)

  timers[name].period       = timer.period
  timers[name].username     = timer.username
  timers[name].password     = timer.password
  timers[name].certificate  = timer.certificate
  timers[name].retries      = 0
end


local function delete_timer(name)
  local id = timers[name].id
  log("deleting timer of auto-rotating jwks for ", name, ", timer_id: ", id)

  timers[name] = nil
end


local targets = {}
for _, target in ipairs({
  "access_token_jwks_uri",
  "access_token_keyset",
  "channel_token_jwks_uri",
  "channel_token_keyset",
}) do
  tb_insert(targets, {
    name                = target,
    rotate_period       = target .. "_rotate_period",
    client_username     = target .. "_client_username",
    client_password     = target .. "_client_password",
    client_certificate  = target .. "_client_certificate",
  })
end

function _M.configure(configs)
  log("run configure()")
  -- control planes won't run configure(), so no need to check here
  -- to avoid duplicate rotation, only worker0 does this.
  if ngx.worker.id() ~= 0 then
    return
  end

  local new_timers = {}

  if configs then
    for _, config in ipairs(configs) do
      for _, target in ipairs(targets) do
        local name = config[target.name]
        local period = config[target.rotate_period]
        if name and period > 0 then
          local username = config[target.client_username]
          local password = config[target.client_password]
          local certificate = config[target.client_certificate]
          if new_timers[name] then
            -- To save on the number of timers used, only one timer
            -- is created for every name.
            -- If there are inconsistencies in the configured periods,
            -- the smaller value will win. It's intuitive.
            new_timers[name].period = min(new_timers[name].period, period)

          else
            new_timers[name] = { period = period, username = username,
                                 password = password, certificate = certificate }
          end
        end
      end
    end
  end

  for name, new_timer in pairs(new_timers) do
    if timers[name] then
      update_timer(name, new_timer)

    else
      create_timer(name, new_timer)
    end
  end

  for name in pairs(timers) do
    if not new_timers[name] then
      delete_timer(name)
    end
  end
end

return _M
