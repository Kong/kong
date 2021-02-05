local kong = kong


local function debug(msg)
  if kong then
    kong.log.debug(msg)
  end
end

local function process_decision(opa_decision)
  -- decision is absent from response
  if not opa_decision or
    not type(opa_decision) == "table" or
    type(opa_decision.result) == "nil" then
      return nil, nil, "invalid decision result from OPA server"
  end

  local result = opa_decision.result

  if type(result) == "boolean" then
    -- boolean result
    -- either let the request through or return 4xx
    if result then
      debug("opa returned a positive decision")
      return true, nil, nil
    else
      debug("opa returned a negative decision")
      return false, nil, nil
    end
  end

  if type(result) == "table" then
    -- detailed decision returned from OPA
    debug("opa returned a table decision")

    if type(result.allow) ~= "boolean" then
      return nil, nil, "invalid response from OPA server"
    end

    if result.allow then
      debug("opa returned a positive decision")
    else
      debug("opa returned a negative decision")
    end

    return result.allow, { headers = result.headers, status = result.status }, nil
  end

  return nil, nil, "invalid response from OPA server"
end


return {
  process_decision = process_decision
}

