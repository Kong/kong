-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  name         = "event_hooks",
  primary_key  = { "id" },
  endpoint_key = "id",
  subschema_key = "handler",
  -- disable auto admin API to manually map /event-hooks routes
  generate_admin_api = false,
  -- XXX: foreign key support like plugins:
  -- routes / services / consumers ?
  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { updated_at     = typedefs.auto_timestamp_s },
    { source         = { description = "The source of the event hook.", type = "string", required = true } },
    { event          = { description = "The event associated with the hook.", type = "string" } },
    { on_change      = { description = "Indicates whether the hook should be triggered on change.", type = "boolean" } },
    { snooze         = { description = "The snooze duration for the hook.", type = "integer" } },
    { handler        = { description = "The handler for the event hook.", type = "string", required = true } },
    { config         = { description = "The configuration for the event hook.", type = "record", required = true, abstract = true } },
  },
}
