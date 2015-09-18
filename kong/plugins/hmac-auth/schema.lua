local function check_clock_skew_positive(v)
  if v and v < 0 then
    return false, "Clock Skew should be positive"
  end
  return true
end

return {
  no_consumer = true,
  fields = {
    hide_credentials = { type = "boolean", default = false },
    clock_skew = { type = "number", default = 300, func = check_clock_skew_positive }
  }
}
