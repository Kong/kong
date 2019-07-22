local strategy = require('kong.plugins.gql-proxy-cache.strategies')
local md5 = ngx.md5
local build_ast = require("kong.gql.build_ast")
local gql_util = require('kong.gql.util')

local _GqlCacheHandler = {
    VERSION = "1.2.1",
    PRIORITY = 100
}


function _GqlCacheHandler:init_worker()

end


-- Determines if query operation is cacheable
local function cacheable_req(ast)
    return ast.is_query_op()
end


-- Build cache key from current subtree
-- @param subtree:
-- @param conf: plugin configuration table
-- @param(opt) path_key: Cache key of current tree context
local function build_cache_key(service_id, cache_key, conf, path_key)

end


-- Stringify keys in alphabetical order
local function _prefix_args(arguments)

    for k, v in pairs(arguments) do

    end


end


-- @param node: node has 1 or more arguments
local function _prefix_node(node)
    local arg_digest = _prefix_args(node.arguments)
    return string.format("%s(%s)", node.name, arg_digest)
end


local function cache_traverse_find(subtree, path_key, forward_req)
    local node_digest = _prefix_node(subtree.node)
    local key = md5(string.format("%s|%s"), path_key, node_digest)

    local res, err = strategy:fetch(key)
    if err then
        return nil, subtree
    end

    -- res is table of subtree's response along with all subtrees of no arguments
    local children_w_args = gql_util.filter_iter(
            subtree.node:children(),
            function (node)
                for _ in pairs(node.arguments) do return true end
                return false
            end
    )

    -- TODO: account for field nodes missing from found subtree
    for node in children_w_args do
        local c_res, c_forward = cache_traverse_find(node, key, new_context)

        -- TODO: Should accumulate into array and merge at the end
        res = response_merge(res, node.name, c_result)
        forward_req = upstream_forward_merge(forward_req, node.name, c_forward)
    end

    return res, forward_req
end


-- Store what is needed of the response by traversing tree
-- @param subtree_node: node of subtree
-- @param 
-- @param res_context: current context of upstream response
local function cache_traverse_store(subtree_node, path_key, res_context)

    local key = build_cache_key(subtree_node, path_key)

    local raw_res = strategy:has(key)
    if not raw_res then

    end

    -- Here, we merge responses
    local res = deserialize(raw_res)

end


function _GqlCacheHandler:access()

    local body = kong.request.get_body()
    local gql_op = body.query

    local ok, result = pcall(build_ast, gql_op)
    if not ok then
        kong.log.err(result)
        return kong.response.exit(400, {
            err = '[GqlBaseErr]: internal parsing',
            message = result
        }, { ['Content-Type'] = 'application/json' })
    end

    if not cacheable_req(result) then
        ngx.header["X-Cache-Status"] = "Bypass"
        return
    end

    -- Compute miss or hit type


    -- Compute upstream request if partial hit type

end


function _GqlCacheHandler:body_filter()
    -- Path 1: Glue together response if partial hit

    -- Path 2: If miss, save to cache each subtree with arguments

end


return _GqlCacheHandler
