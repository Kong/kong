
local function calculate_cost(ast, node)
    local total_cost = 0
    for child in ast:get_children_iter(node) do
        total_cost = total_cost + calculate_cost(ast, child)
    end

    local total_add = ast:get_data(node, "add_constant") or 1
    local total_mul = ast:get_data(node, "mul_constant") or 1

    local a_lst = ast:get_data(node, "add_arguments") or {}
    for _, add_arg in ipairs(a_lst) do
        if ast:get_argument(node, add_arg) ~= nil then
            total_add = total_add + ast:get_argument(node, add_arg)
        end
    end

    local m_lst = ast:get_data(node, "mul_arguments") or {}
    for _, mul_arg in ipairs(m_lst) do
        if ast:get_argument(node, mul_arg) ~= nil then
            total_mul = total_mul * ast:get_argument(node, mul_arg)
        end
    end

    return total_cost * total_mul + total_add
end


return function (query_ast)
    local op_node = query_ast:get_op_node()
    return calculate_cost(query_ast, op_node)
end
