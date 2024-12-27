# RPC Mock

This is a module for incercept and manipulate Kong's RPC calls between CP & DP.

## CP

Visually we will get a mocked CP by calling:

```lua
local mocked_cp = require("spec.helpers.rpc_mock.cp").new()
mocked_cp:start()
```

This starts a working Kong CP, with all the funcitionalities and acts like normal CPs, except for that it can be manipulated with the `mocked_cp` object.

Arguments can be used to alter the control planes's options (or attach to an existing CP) or not to start incerception by default, etc.

Then we can let CP make a call to a specific node connected:

```lua
local res, err = mocked_cp:call(node1_uuid, "kong.sync.v2.notify_new_version", payload)
```

And we can incercept a call to the mocked CP:

```lua
for _, record in pairs(mocked_cp.records) do
    print("DP ", record.nodeid, " made a call ", record.method)
    print(plprint(record.request))
    print(plprint(record.response))
end
```

We can also mock an API. (Note that the original handler will be overrided.)

## DP

This is bascially an extended version of `kong.clustering.rpc.manager`.

Added API:

```lua
local mocked_dp = require("spec.helpers.rpc_mock.dp").new()
mocked_dp:try_connect()
mocked_dp:wait_until_connected()
assert(mocked_dp:is_connected())
mocked_dp:stop()
```
