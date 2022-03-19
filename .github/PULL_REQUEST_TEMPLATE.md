<!--
NOTE: Please read the CONTRIBUTING.md guidelines before submitting your patch,
and ensure you followed them all:
https://github.com/Kong/kong/blob/master/CONTRIBUTING.md#contributing
-->

### Summary

<!--- Why is this change required? What problem does it solve? -->

### Full changelog

* [Implement ...]
* [Add related tests]
* ...

### Issue reference

<!--- If it fixes an open issue, please link to the issue here. -->
Fix #_[issue number]_
Summary
This makes the cache_key function more robust. For example this code may be quite common:

local route = kong.db.routes:select_by_name("my-route")
-- {
--   id = ...,
--   name = "my-route",
--   ...
--   service = {
--     id = ...
--   }
-- }

local cache_key = kong.db.services:cache_key(route.service)
Now if service schema has cache_key = { "name" } (it does not, but just as an example) you can see that the local cache_key will then be same for all the services (no matter if they are pointing to different service by id), as the route.service is not expanded by default, and it only contains the primary key, in this case id.

The change in this commit is that it will now actually fallback to primary_key = { "id" } in case it cannot find anything by the cache_key. As it can be seen in code above, it is quite easy to make this mistake, and not see the mistake. User could fix their code by calling:

local cache_key = kong.db.services:cache_key(route.service.id)
instead of:

local cache_key = kong.db.services:cache_key(route.service)
But as this can potentially be dangerous if forgotten, I think it is worth to fallback to primary_key by default on such case.
