-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ffi = require "ffi"

local NAMESPACES = {
  {
    prefix = "saml",
    href = "urn:oasis:names:tc:SAML:2.0:assertion",
  },
  {
    prefix = "samlp",
    href = "urn:oasis:names:tc:SAML:2.0:protocol",
  },
  {
    prefix = "md",
    href = "urn:oasis:names:tc:SAML:2.0:metadata",
  },
  {
    prefix = "dsig",
    href = "http://www.w3.org/2000/09/xmldsig#",
  },
  {
    prefix = "xenc",
    href = "http://www.w3.org/2001/04/xmlenc#",
  },
}


local function evaluate_xpath(node, xpath)
  if not node then
    return nil, "XPath " .. xpath .. " could not be evaluated on nil node"
  end

  local result = node:search(xpath, NAMESPACES)
  -- fixme: guard against multiple matches
  if #result == 1 then
    if result[1].node.type == ffi.C.XML_ELEMENT_NODE then
      return result[1]
    else
      return result[1]:content()
    end
  elseif #result > 1 then
    return nil, "XPath " .. xpath .. " unexpectedly yielded multiple matches"
  end
  return nil
end


return {
  evaluate = evaluate_xpath,
}
