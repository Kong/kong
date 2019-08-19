local function base_initiator(self, ctx)
  return self
          :set_ctx(ctx)
          :next()
end


return {
  table   = base_initiator,
  number  = base_initiator,
  string  = base_initiator,
  boolean = base_initiator
}
