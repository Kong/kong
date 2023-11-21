-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local match = string.match


local _M = {}


--- Extract the parent domain of CN and CN itself from X509 certificate
-- @tparam resty.openssl.x509 x509 the x509 object to extract CN
-- @return cn (string) CN + parent (string) parent domain of CN, or nil+err if any
function _M.get_cn_parent_domain(x509)
  local name, err = x509:get_subject_name()
  if err then
    return nil, err
  end
  local cn, _, err = name:find("CN")
  if err then
    return nil, err
  end
  cn = cn.blob
  local parent = match(cn, "^[%a%d%*-]+%.(.+)$")
  return cn, parent
end


return _M
