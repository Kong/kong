-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local deflate_gzip = require("kong.tools.gzip").deflate_gzip
local ai_plugin_ctx = require("kong.llm.plugin.ctx")

local get_global_ctx, _ = ai_plugin_ctx.get_global_accessors("_base")

-- Our own "phases", to avoid confusion with Kong's phases we use a different name
local STAGES = {
  SETUP = 0,

  REQ_INTROSPECTION = 1,
  REQ_TRANSFORMATION = 2,

  REQ_POST_PROCESSING = 3,
  RES_INTROSPECTION = 4,
  RES_TRANSFORMATION = 5,

  STREAMING = 6,

  RES_POST_PROCESSING = 7,
}

local MetaPlugin = {}

local all_filters = {}

local function run_stage(stage, sub_plugin, conf)
  local _filters = sub_plugin.filters[stage]
  if not _filters then
    return
  end

  -- if ngx.ctx.ai_executed_filters is not set, meaning we are before access phase
  -- just provide empty table to make following logic happy
  local ai_executed_filters = ngx.ctx.ai_executed_filters or {}

  for _, name in ipairs(_filters) do
    local f = all_filters[name]
    if not f then
      kong.log.err("no filter named '" .. name .. "' registered")

    elseif not ai_executed_filters[name] then
      ai_executed_filters[name] = true

      kong.log.debug("executing filter ", name)

      local ok, err = f:run(conf)
      if not ok then
        kong.log.err("error running filter '", name, "': ", err)
        local phase = ngx.get_phase()
        if phase == "access" or phase == "header_filter" then
          return kong.response.exit(500)
        end
        return ngx.exit(500)
      end
    end
  end
end

function MetaPlugin:init_worker(sub_plugin)
  run_stage(STAGES.SETUP, sub_plugin)
end


function MetaPlugin:configure(sub_plugin, configs)
  run_stage(STAGES.SETUP, sub_plugin, configs)
end

function MetaPlugin:access(sub_plugin, conf)
  ngx.ctx.ai_namespaced_ctx = ngx.ctx.ai_namespaced_ctx or {}
  ngx.ctx.ai_executed_filters = ngx.ctx.ai_executed_filters or {}

  if sub_plugin.enable_balancer_retry then
    kong.service.set_target_retry_callback(function()
      ngx.ctx.ai_executed_filters = {}

      MetaPlugin:retry(sub_plugin, conf)

      return true
    end)
  end

  run_stage(STAGES.REQ_INTROSPECTION, sub_plugin, conf)
  run_stage(STAGES.REQ_TRANSFORMATION, sub_plugin, conf)
end


function MetaPlugin:retry(sub_plugin, conf)
  run_stage(STAGES.REQ_TRANSFORMATION, sub_plugin, conf)
end

function MetaPlugin:rewrite(sub_plugin, conf)
  -- TODO
end

function MetaPlugin:header_filter(sub_plugin, conf)
  -- for error and exit response, just use plaintext headers
  if kong.response.get_source() == "service" then
    -- we use openai's streaming mode (SSE)
    if get_global_ctx("stream_mode") then
      -- we are going to send plaintext event-stream frames for ALL models
      kong.response.set_header("Content-Type", "text/event-stream")
      -- TODO: disable gzip for SSE because it needs immediate flush for each chunk
      -- and seems nginx doesn't support it

    elseif get_global_ctx("accept_gzip") then
      kong.response.set_header("Content-Encoding", "gzip")
    end

  else
    kong.response.clear_header("Content-Encoding")
  end

  run_stage(STAGES.REQ_POST_PROCESSING, sub_plugin, conf)
  -- TODO: order this in better place
  run_stage(STAGES.RES_INTROSPECTION, sub_plugin, conf)
  run_stage(STAGES.RES_TRANSFORMATION, sub_plugin, conf)
end

function MetaPlugin:body_filter(sub_plugin, conf)
  -- check if a response is already sent in access phase by any filter
  local sent, source = get_global_ctx("response_body_sent")
  if sent then
    kong.log.debug("response already sent from source: ", source, " skipping body_filter")
    return
  end

  -- check if we have generated a full body
  local body, source = get_global_ctx("response_body")
  if body and source ~= ngx.ctx.ai_last_sent_response_source then
    assert(source, "response_body source not set")

    if get_global_ctx("accept_gzip") then
      body = deflate_gzip(body)
    end

    ngx.arg[1] = body
    ngx.arg[2] = true
    kong.log.debug("sent out response from source: ", source)

    ngx.ctx.ai_last_sent_response_source = source
    return
  end

  -- else run the streaming handler
  run_stage(STAGES.STREAMING, sub_plugin, conf)
end

function MetaPlugin:log(sub_plugin, conf)
  run_stage(STAGES.RES_POST_PROCESSING, sub_plugin, conf)
end


local _M = {
  STAGES = STAGES,
}

function _M.define(name, priority)
  return setmetatable({
    name = name,
    priority = priority,
    filters = {},
    balancer_retry_enabled = false,
  }, { __index = _M })
end

-- register a filter into the runtime
function _M.register_filter(f)
  if not f or type(f.run) ~= "function" then
    error("expected a filter with a 'run' method", 2)
  end

  local stage = f.STAGE

  if not stage then
    error("expected a filter with a 'STAGE' property", 2)
  end

  if not STAGES[stage] then
    error("unknown stage: " .. stage, 2)
  end

  local filter_name = f.NAME

  if not filter_name then
    error("expected a filter with a 'NAME' property", 2)
  end

  if all_filters[filter_name] then
    return all_filters[filter_name]
  end

  all_filters[filter_name] = f

  return f
end

-- enable the filter for current sub plugin
function _M:enable(filter)
  if type(filter) ~= "table" or not filter.NAME then
    error("expected a filter table with a 'NAME' property", 2)
  end

  if not all_filters[filter.NAME] then
    error("unregistered filter: " .. filter.NAME, 2)
  end

  -- the filter has done sanity test when registering

  local stage_id = STAGES[filter.STAGE]

  if not self.filters[stage_id] then
    self.filters[stage_id] = {}
  end

  table.insert(self.filters[stage_id], filter.NAME)
end

function _M:enable_balancer_retry()
  self.balancer_retry_enabled = true
end

function _M:as_kong_plugin()
  local Plugin = {
    PRIORITY = self.priority,
    VERSION = require("kong.meta").core_version
  }

  if self.filters[STAGES.SETUP] then
    Plugin.init_worker = function(_)
      return MetaPlugin:init_worker(self)
    end

    Plugin.configure = function(_, configs)
      return MetaPlugin:configure(self, configs)
    end
  end

  if self.filters[STAGES.REQ_INTROSPECTION] or self.filters[STAGES.REQ_TRANSFORMATION] then
    Plugin.access = function(_, conf)
      return MetaPlugin:access(self, conf)
    end
  end

  -- TODO: XXX
  -- rewrite = function(_, conf)
  --   return MetaPlugin:rewrite(self, conf)
  -- end,

  if self.filters[STAGES.REQ_POST_PROCESSING] or self.filters[STAGES.RES_INTROSPECTION] or self.filters[STAGES.RES_TRANSFORMATION] then
    Plugin.header_filter = function(_, conf)
      return MetaPlugin:header_filter(self, conf)
    end
  end

  if self.filters[STAGES.STREAMING] then
    Plugin.body_filter = function(_, conf)
      return MetaPlugin:body_filter(self, conf)
    end
  end

  if self.filters[STAGES.RES_POST_PROCESSING] then
    Plugin.log = function(_, conf)
      return MetaPlugin:log(self, conf)
    end
  end

  return Plugin
end

return _M