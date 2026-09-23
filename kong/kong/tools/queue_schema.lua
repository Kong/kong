local Schema = require "kong.db.schema"

-- TODO: enable the descriptions once they are accepted in Schemas
return Schema.define {
  type = "record",
  fields = {
    { max_batch_size = {
      type = "integer",
      default = 1,
      between = { 1, 1000000 },
      description = "Maximum number of entries that can be processed at a time."
    } },
    { max_coalescing_delay = {
      type = "number",
      default = 1,
      between = { 0, 3600 },
      description = "Maximum number of (fractional) seconds to elapse after the first entry was queued before the queue starts calling the handler.",
      -- This parameter has no effect if `max_batch_size` is 1, as queued entries will be sent
      -- immediately in that case.
    } },
    { max_entries = {
      type = "integer",
      default = 10000,
      between = { 1, 1000000 },
      description = "Maximum number of entries that can be waiting on the queue.",
    } },
    { max_bytes = {
      type = "integer",
      default = nil,
      description = "Maximum number of bytes that can be waiting on a queue, requires string content.",
    } },
    { max_retry_time = {
      type = "number",
      default = 60,
      description = "Time in seconds before the queue gives up calling a failed handler for a batch.",
      -- If this parameter is set to -1, no retries will be made for a failed batch
    } },
    {
      initial_retry_delay = {
        type = "number",
        default = 0.01,
        between = { 0.001, 1000000 }, -- effectively unlimited maximum
        description = "Time in seconds before the initial retry is made for a failing batch."
        -- For each subsequent retry, the previous retry time is doubled up to `max_retry_delay`
    } },
    { max_retry_delay = {
      type = "number",
      default = 60,
      between = { 0.001, 1000000 }, -- effectively unlimited maximum
      description = "Maximum time in seconds between retries, caps exponential backoff."
    } },
    { concurrency_limit = {
      type = "integer",
      default = 1,
      one_of = { -1, 1 },
      description = "The number of of queue delivery timers. -1 indicates unlimited."
    } },

  }
}
