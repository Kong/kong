return {
  limit = { required = true },
  period = { required = true, enum = { "second", "minute", "hour", "day", "month", "year" } }
}
