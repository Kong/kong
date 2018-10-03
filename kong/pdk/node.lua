--- Node-level utilities
--
-- @module kong.node

local utils = require "kong.tools.utils"


local NODE_ID_KEY = "kong:node_id"


local node_id


local function new(self)
  local _NODE = {}


  ---
  -- Returns the id used by this node to describe itself.
  --
  -- @function kong.node.get_id
  -- @treturn string The v4 UUID used by this node as its id
  -- @usage
  -- local id, err = kong.node.get_id()
  function _NODE.get_id()
    if node_id then
      return node_id
    end

    local shm = ngx.shared.kong

    local ok, err = shm:safe_add(NODE_ID_KEY, utils.uuid())
    if not ok and err ~= "exists" then
      error("failed to set 'node_id' in shm: " .. err)
    end

    node_id, err = shm:get(NODE_ID_KEY)
    if err then
      error("failed to get 'node_id' in shm: " .. err)
    end

    if not node_id then
      error("no 'node_id' set in shm")
    end

    return node_id
  end


  return _NODE
end


return {
  new = new,
}
