## Dynamic hooks

Dynamic hooks can be used to extend Kong's behavior and run code at specific stages in the request/response lifecycle.


### Principles of operation

This module provides a way to define, enable, and execute dynamic hooks in Kong. It also allows hooking "before" and "after" handlers to functions, that are patched to execute them when called.
Dynamic Hooks can be organized into groups, allowing to enable or disable sets of hooks collectively.

Dynamic Hooks are intended solely for internal use. Usage of this feature is at your own risk.


#### Example usage

```lua
local dynamic_hook = require "kong.dynamic_hook"

----------------------------------------
-- Define a hook handler
local function before_hook(...)
  io.write("hello, ")
end

-- Hook a function
dynamic_hook.hook_function("my_group", _G, "print", "varargs", {
  befores = { before_hook },
})

-- Enable the hook group
dynamic_hook.enable_by_default("my_group")

-- Call the function
print("world!") -- prints "hello, world!"

----------------------------------------
-- Define another hook handler
local function log_event_hook(arg1, arg2)
  ngx.log(ngx.INFO, "event triggered with args: ", arg1, ", ", arg2)
end

-- Register a new hook
dynamic_hook.hook("event_group", "log_event", log_event_hook)

-- Enable the hook group for this request
dynamic_hook.enable_on_this_request("event_group")

-- Run the hook
dynamic_hook.run_hook("event_group", "log_event", 10, "test")
```


### Application in Kong Gateway

Kong Gateway defines, registers and runs the following hooks:


| Hook | Description | Run Location |
| ----------- | ----------- | ----------- |
| timing:auth - auth | (Timing module) enables request debugging<br>for requests that match the requirements | Kong.rewrite (beginning) |
| timing - before:rewrite | (Timing module) enters the "rewrite" context, to begin<br>measuring the rewrite phase's duration | Kong.rewrite (beginning) |
| timing - after:rewrite | (Timing module) exits the "rewrite" context, to end<br>measuring the rewrite phase's duration | Kong.rewrite (end) |
| timing - dns:cache_lookup | (Timing module) sets the cache_hit context property | During each in-memory DNS cache lookup |
| timing - before:balancer | (Timing module) enters the "balancer" context, to begin<br>measuring the balancer phase's duration | Kong.balancer (beginning) |
| timing - after:balancer | (Timing module) exits the "balancer" context, to end<br>measuring the balancer phase's duration | Kong.balancer (end) |
| timing - before:access | (Timing module) enters the "access" context, to begin<br>measuring the access phase's duration | Kong.access (beginning) |
| timing - before:router | (Timing module) enters the router's context, to begin<br>measuring the router's execution | Before router initialization |
| timing - after:router | (Timing module) exits the router's context, to end<br>measuring the router's execution | After router execution |
| timing - workspace_id:got | (Timing module) sets the workspace_id context property | Kong.access, after workspace ID assignment |
| timing - after:access | (Timing module) exits the "access" context, to end<br>measuring the access phase's duration | Kong.access (end) |
| timing - before:response | (Timing module) enters the "response" context, to begin<br>measuring the response phase's duration | Kong.response (beginning) |
| timing - after:response | (Timing module) exits the "response" context, to end<br>measuring the response phase's duration | Kong.response (end) |
| timing - before:header_filter | (Timing module) enters the "header_filter" context, to begin<br>measuring the header_filter phase's duration | Kong.header_filter (beginning) |
| timing - after:header_filter | (Timing module) exits the "header_filter" context, to end<br>measuring the header_filter phase's duration | Kong.header_filter (end) |
| timing - before:body_filter | (Timing module) enters the "body_filter" context, to begin<br>measuring the body_filter phase's duration | Kong.body_filter (beginning) |
| timing - after:body_filter | (Timing module) exits the "body_filter" context, to end<br>measuring the body_filter phase's duration | Kong.body_filter (end) |
| timing - before:log | (Timing module) enters the "log" context, to begin<br>measuring the log phase's duration | Kong.log (beginning) |
| timing - after:log | (Timing module) exits the "log" context, to end<br>measuring the log phase's duration | Kong.log (end) |
| timing - before:plugin_iterator | (Timing module) enters the "plugins" context, to begin<br>measuring the plugins iterator's execution | Before plugin iteration starts |
| timing - after:plugin_iterator | (Timing module) exits the "plugins" context, to end<br>measuring the plugins iterator's execution | After plugin iteration ends |
| timing - before:plugin | (Timing module) enters each plugin's context, to begin<br>measuring the plugin's execution | Before each plugin handler |
| timing - after:plugin | (Timing module) exits each plugin's context, to end<br>measuring the plugin's execution | After each plugin handler |


"timing" hooks are used by the timing module when the request debugging feature is enabled.

The following functions are patched using `hook_function`:

| Function | Description |
| ----------- | ----------- |
| resty.dns.client.toip | (Timing module) measure dns query execution time  |
| resty.http.connect | (Timing module) measure http connect execution time |
| resty.http.request | (Timing module) measure http request execution time |
| resty.redis.{method} | (Timing module) measure each Redis {method}'s<br> execution time |
| ngx.socket.tcp | (Timing module) measure each tcp connection<br>and ssl handshake execution times |
| ngx.socket.udp | (Timing module) measure each udp "setpeername"<br>execution time |
