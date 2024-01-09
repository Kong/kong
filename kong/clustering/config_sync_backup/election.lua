-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- this module provides shared utilities for s3 and gcs strategies to elect a leader
-- which is responsible for exporting the configuration to the storage
local _M = {}

local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_DEBUG = ngx.DEBUG
local ngx_now = ngx.now
local ngx_timer_at = ngx.timer.at
local tonumber = tonumber


-- log message prefix
local FALLBACK_CONFIG_PREFIX = "[fallback config] "
local DEFAULT_MARGIN = 5


-- storage needs to implement:
--   function register_node()
--     register and refresh the node record
--   function get_candidates()
--     Get an iterator of the candidates. Every item is a table with the following fields:
--     {node_id, timestamp}
--     and it's storage's responsibility to filter out unfresh nodes.
--     the freshness is checked based on election_interval.
--     for example storage may attach a TTL to the node record;
--     but for s3/gcs, TTL does not work on this precision, and we need to
--     filter out the unfresh nodes according to their last-modified time
function _M.new(opts)
  local self = {
    set_enable_export = opts.set_enable_export,
    election_interval = opts.election_interval,
    node_id = kong.node.get_id(),
    storage = opts.storage,
  }

  return setmetatable(self, { __index = _M })
end


function _M:register()
  -- first time register
  if not self.register_time then
    self.register_time = ngx_now()
  end

  return self.storage:register_node(self.node_id, self.register_time)
end


function _M:elect_leader()
  local leader
  local iter, err = self.storage:get_candidates()
  if not iter then
    return nil, err
  end

  for candidate in iter do
    if not leader then
      leader = candidate

    elseif candidate.register_time < leader.register_time then
      leader = candidate

    elseif candidate.register_time == leader.register_time then
      if candidate.node_id < leader.node_id then
        leader = candidate
      end
    end
  end

  if leader == nil then
    return nil, "no candidates found"
  end

  return leader
end


local function election_loop_timer_impl(election)
  ngx_log(ngx_DEBUG, FALLBACK_CONFIG_PREFIX, "new round of election. registering with uuid: ", election.node_id)

  local ok, err = election:register()
  if not ok then
    ngx_log(ngx_ERR, FALLBACK_CONFIG_PREFIX, "failed to register node: ", err)
    return
  end

  ngx_log(ngx_DEBUG, FALLBACK_CONFIG_PREFIX, "selecting leader")

  local leader, err = election:elect_leader()
  if not leader then
    ngx_log(ngx_ERR, FALLBACK_CONFIG_PREFIX, "failed to elect leader: ", err)
    return
  end

  if leader.node_id == election.node_id then
    ngx_log(ngx_INFO, FALLBACK_CONFIG_PREFIX, "node is chosen as leader. Enabling exporting.")
    election.set_enable_export(true)

  else
    ngx_log(ngx_DEBUG, FALLBACK_CONFIG_PREFIX, "leader is ", leader.node_id)
    election.set_enable_export(false)
  end
end


local function election_loop_timer(premature, election)
  if premature then
    return
  end

  election_loop_timer_impl(election)

  -- we do not take the time spent in election_loop_timer_impl into account
  -- because if it really takes that long, we should not put even more pressure to S3/GCS
  local ok, err = ngx_timer_at(election.election_interval, election_loop_timer, election)
  if not ok then
    ngx_log(ngx_ERR, FALLBACK_CONFIG_PREFIX, "failed to start election timer: ", err)
  end
end


function _M:start_timer()
  -- use a random delay to avoid potential collision of leader election
  -- we want a random delay between 0 and min(5, `election_interval`) seconds with 0.01 seconds granularity
  local random_delay = math.random(0, math.min(5, self.election_interval) * 100) / 100

  local ok, err = ngx_timer_at(random_delay, election_loop_timer, self)
  if not ok then
    ngx_log(ngx_ERR, FALLBACK_CONFIG_PREFIX, "failed to start elect timer for the first time:", err)
  end
end


---- below are default implementations of object naming and freshness checking

function _M.parse_node_information(prefix, name)
  local prefix_len = #prefix
  local file_name = name:sub(prefix_len + 1)
  local register_time, node_id = file_name:match("^(%d+.?%d*)-(.+)$")
  if not node_id or not register_time then
    ngx_log(ngx_ERR, FALLBACK_CONFIG_PREFIX, "failed to parse a registion object key: ", file_name)
    return nil
  end

  return {
    node_id = node_id,
    register_time = tonumber(register_time),
  }
end


function _M:to_file_name(prefix)
  return prefix .. self.register_time .. "-" .. self.node_id
end


_M.DEFAULT_MARGIN = DEFAULT_MARGIN


function _M:is_fresh(refreshed_time, now)
  return (now or ngx_now()) <= (refreshed_time + self.election_interval + DEFAULT_MARGIN)
end

return _M
