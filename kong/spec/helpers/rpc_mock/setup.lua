local misc = require("spec.internal.misc")


local recover


--- DP mock requires worker_events and timer to run and they needs to be patched to work properly.
local function setup()
  misc.repatch_timer()
  if not kong.worker_events then
    misc.patch_worker_events()
    recover = true
  end
end


local function teardown()
  misc.unrepatch_timer()
  if recover then
    kong.worker_events = nil
  end
end


return {
  setup = setup,
  teardown = teardown,
}