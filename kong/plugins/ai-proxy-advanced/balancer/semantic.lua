-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local balancers = require "kong.runloop.balancer.balancers"
local get_tried_targets = require "kong.plugins.ai-proxy-advanced.balancer.state".get_tried_targets
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local vectordb = require("kong.llm.vectordb")
local embeddings     = require("kong.llm.embeddings")
local sha256_hex     = require("kong.tools.sha256").sha256_hex

local algorithm = {}
algorithm.__index = algorithm


function algorithm:afterHostUpdate()
  local embeddings_driver, err = embeddings.new(self.embeddings_conf, self.vectordb_conf.dimensions)
  if not embeddings_driver then
    return false, "failed to initialize embeddings driver: " .. err
  end

  local vectordb_driver, err = vectordb.new(self.vectordb_conf.strategy, self.namespace, self.vectordb_conf)
  if not vectordb_driver then
    return false, "failed to initialize semantic cache driver: " .. err
  end

  self._target_id_map = {}

  -- calculate the vector of each target
  for _, target in ipairs(self.targets) do
    assert(target.description)
    local keyid = sha256_hex(target.description)

    self._target_id_map[keyid] = target

    local embedding, _, err = embeddings_driver:generate(target.description)
    if err then
      return false, "unable to generate embeddings for target: " .. err
    end

    local _, err = vectordb_driver:insert(embedding, {hash=keyid}, keyid)
    if err then
      return false, "unable to set cache for target: " .. err
    end

  end

  return true
end

local function get_request_body(_)
  -- if plugin ordering was altered, receive the "decorated" request
  local request_body_table = ai_plugin_ctx.get_request_body_table_inuse()
  if not request_body_table then
    return nil, "this LLM route only supports application/json requests"
  end

  if not (type(request_body_table) == "table"
    and type(request_body_table.messages) == "table"
    and #request_body_table.messages > 0) then

    return nil, "this LLM route only supports chat requests"
  end

  if not request_body_table and ngx.get_phase() ~= "access" then
    return nil, "too late to read body"
  end

  return request_body_table
end

local function serialize_body(self)
  local request, err = get_request_body(self)
  if err then
    return nil, err
  end

  for i = #request.messages, 1, -1 do
    local message = request.messages[i]
    if message and message.role == "user" then
      return message.content
    end
  end

  return nil, "no user message found in the request"
end

local metadata_t = {}

function algorithm:getPeer(_)
  if #get_tried_targets() > 0 then
    kong.log.warn("semantic routing doesn't currently support fail-over")
    return nil, balancers.errors.ERR_NO_PEERS_AVAILABLE .. ": semantic routing doesn't currently support fail-over"
  end

  local message, err = serialize_body(self)
  if err then
    if ngx.get_phase() == "access" then
      return kong.response.exit(400, { message = err })
    else -- usually we shouldn't reach here, but if we do, fail hard
      error(err, 2)
    end
  end

  local vectordb_conf = self.vectordb_conf

  local embeddings_driver, err = embeddings.new(self.embeddings_conf, vectordb_conf.dimensions)
  if not embeddings_driver then
    return false, "failed to initialize embeddings driver: " .. err
  end

  local vectordb_driver, err = vectordb.new(vectordb_conf.strategy, self.namespace, vectordb_conf)
  if not vectordb_driver then
    return false, "failed to initialize semantic cache driver: " .. err
  end

  local embedding, _, err = embeddings_driver:generate(message)
  if not embedding then
    return nil, "unable to generate embeddings for request: " .. err
  end

  local target_id, err = vectordb_driver:search(embedding, vectordb_conf.threshold, metadata_t)
  target_id = target_id and target_id.hash

  if err then
    return nil, "unable to get cache for request: " .. err
  elseif target_id then
    if metadata_t.score then
      kong.log.debug("[semantic] found target with ID ", target_id, " with score ", metadata_t.score)
    end

    local target = self._target_id_map[target_id]
    if target then
      return target
    else
      return nil, "found target with ID " .. target_id .. " but it's not mapped to a target"
    end
  end

  kong.log.warn("no target can be found under threshold ", vectordb_conf.threshold,
                  ", consider increase threshold or reword the description of targets" )

  return nil, balancers.errors.ERR_NO_PEERS_AVAILABLE .. ": consider increase threshold or reword the description of targets"
end


function algorithm:afterBalance()
  return true -- noop
end


function algorithm:cleanup()
  local vectordb_driver, err = vectordb.new(self.vectordb_conf.strategy, self.namespace, self.vectordb_conf)
  if not vectordb_driver then
    return false, "failed to initialize semantic cache driver: " .. err
  end

  local good = true
  local ok, err = vectordb_driver:drop_index()
  if not ok then
    good = false
    kong.log.warn("failed to delete cache for target: ", err)
  end

  return good, not good and "error occured during cleanup" or nil
end


function algorithm.new(targets, conf)
  local self = setmetatable({
    vectordb_conf = conf.vectordb,
    embeddings_conf = conf.embeddings,
    max_request_body_size = conf.max_request_body_size,
    namespace = "ai_proxy_advanced_semantic:" .. conf.__plugin_id,
    targets = targets or {},
    _target_id_map = {},
  }, algorithm)

  local ok, err = self:afterHostUpdate()
  if not ok then
    return nil, err
  end

  return self
end

return algorithm
