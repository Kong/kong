return {
  limit = { type = "number", required = true },
  period = { type = "string", required = true, enum = { "second", "minute", "hour", "day", "month", "year" } }
}