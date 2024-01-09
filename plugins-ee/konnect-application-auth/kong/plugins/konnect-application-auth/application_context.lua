-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong

-- NOTE: kong.ctx.shared.kaa_application_context is used within
-- kong/analytics/init.lua if the reference changes it needs to be
-- updated over there otherwise it will break the analytics

--- set_context inserts the KAA application context in the kong
--- shared context to be reused accross plugins
--- @param application_context table
local function set_context(application_context)
  if not application_context then return end

  kong.ctx.shared.kaa_application_context = {
    application_id = application_context.application_id,
    portal_id = application_context.portal_id,
    developer_id = application_context.developer_id,
    organization_id = application_context.organization_id,
  }
end

--- get_context returns the KAA application context stored in the
--- kong shared request context
--- @return table application_context
local function get_context()
  return kong.ctx.shared.kaa_application_context
end

return {
  set_context = set_context,
  get_context = get_context,
}
