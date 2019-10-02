-- Cost function that takes everything into consideration
local function bao_cost(ast, node)
    local total_cost = 0
    for child in ast:get_children_iter(node) do
        total_cost = total_cost + bao_cost(ast, child)
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


-- query cost by number of nodes, based on quantifiers
-- ref: https://developer.github.com/v4/guides/resource-limitations/
-- any node that has no quantifier (mul_argument) defined, will not be counted
-- on the cost function.
--
-- Examples:
--
-- Cost: (10 x 20) + 20 + 1 = 221
-- 1 call on allPeople resource (returns max 20)
-- 20 calls to vehicles resource (one for each people)
-- 10 x 20 calls to films (one call for every vehicle, for every people)
--
-- query {
--   allPeople(start: 20) { <-- 1
--     people {
--       id
--       name
--       vehicleConnection(start: 10) {  <-- 20
--         vehicles { id name }
--         filmsConnection(start: 5) {   <-- 10 x 20
--           films { id name }
--         }
--       }
--     }
--   }
-- }
--

local function node_quantifier_cost(ast, node, carriage)
  local total_cost = 0

  local total_add = ast:get_data(node, "add_constant") or 1
  local total_mul = ast:get_data(node, "mul_constant") or 1

  local a_lst = ast:get_data(node, "add_arguments") or {}
  for _, add_arg in ipairs(a_lst) do
    if ast:get_argument(node, add_arg) ~= nil then
      total_add = total_add + ast:get_argument(node, add_arg)
    end
  end

  local has_quantifier_arguments = false

  local m_lst = ast:get_data(node, "mul_arguments") or {}
  for _, mul_arg in ipairs(m_lst) do
    if ast:get_argument(node, mul_arg) ~= nil then
      total_mul = total_mul * ast:get_argument(node, mul_arg)
      has_quantifier_arguments = true
    end
  end

  if has_quantifier_arguments then
    total_cost = carriage * total_add
    carriage = carriage * total_mul
  end

  for child in ast:get_children_iter(node) do
    total_cost = total_cost + node_quantifier_cost(ast, child, carriage)
  end

  return total_cost
end

local cost_functions = {
  ["default"] = function (query_ast, op_node)
    return bao_cost(query_ast, op_node)
  end,
  ["node_quantifier"] = function(query_ast, op_node)
    return node_quantifier_cost(query_ast, op_node, 1)
  end,
}

local function calculate_cost(query_ast, cost_function)
  local cost_function = cost_function or "default"

  if not cost_functions[cost_function] then
    return nil, "cost function " .. cost_function .. " not implemented"
  end

  local op_node = query_ast:get_op_node()

  return cost_functions[cost_function](query_ast, op_node)
end


return function (query_ast, cost_function)
  return calculate_cost(query_ast, cost_function)
end
