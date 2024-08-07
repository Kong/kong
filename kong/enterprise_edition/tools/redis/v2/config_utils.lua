-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.tools.utils"

local function merge_ip_port(node)
  return string.format("%s:%s", node.ip, node.port)
end

local function merge_host_port(node)
  return string.format("%s:%s", node.host, node.port)
end

local function split_ip_port(address)
  local ip = utils.split(address, ':')[1]
  local port = utils.split(address, ':')[2]

  return { ip = ip, port = tonumber(port)}
end

local function split_host_port(address)
  local host = utils.split(address, ':')[1]
  local port = utils.split(address, ':')[2]

  return { host = host, port = tonumber(port)}
end

return {
  merge_ip_port = merge_ip_port,
  merge_host_port = merge_host_port,
  split_ip_port = split_ip_port,
  split_host_port = split_host_port,
}
