### Changed

- The Kong DNS resolver now honors the `MAXNS` setting (3) when parsing the
  `resolv.conf` nameservers.
  [#2290](https://github.com/Mashape/kong/issues/2290)
- Admin API:
  - The "active targets" endpoint now only return the most recent nonzero
    weight Targets, instead of all nonzero weight targets. This is to provide
    a better picture of the Targets currently in use by the Kong load balancer.
    [#2310](https://github.com/Mashape/kong/pull/2310)

### Added

- Ability for the client to chose whether the upstream request (Kong <->
  upstream) should contain a trailing slash in its URI. Prior to this change,
  Kong 0.10 would unconditionally append a trailing slash to all upstream
  requests. The added functionality is now described in
  [#2211](https://github.com/Mashape/kong/issues/2211), and was implemented in
  [#2315](https://github.com/Mashape/kong/pull/2315).
- Plugins:
  - :fireworks: **New Request termination plugin**. This plugin allows to
    temporarily disable an API and return a pre-configured response status and
    body to your client. Useful for use-cases such as maintenance mode for your
    upstream services. Thanks [Paul Austin](https://github.com/pauldaustin)
    for the contribution.
    [#2051](https://github.com/Mashape/kong/pull/2051)
  - logging: Logging plugins now also log the authenticated Consumer.
    [#2367](https://github.com/Mashape/kong/pull/2367)

### Fixed

- Handle a routing edge-case under some conditions with the `uris` matching
  rule of APIs that would falsely lead Kong into believing no API was matched for
  what would actually be a valid request.
  [#2343](https://github.com/Mashape/kong/pull/2343)
- If no API was configured with a `hosts` matching rule, then the
  `preserve_host` flag would never be honored.
  [#2344](https://github.com/Mashape/kong/pull/2344)
- When using Cassandra, some migrations would not be performed on the same
  coordinator as the one originally chosen. The same migrations would also
  require a response from other replicas in a cluster, but were not waiting
  for a schema consensus beforehand, causing undeterministic failures in the
  migrations, especially if the cluster's inter-nodes communication is slow.
  [#2326](https://github.com/Mashape/kong/pull/2326)
- Ensure the `cassandra_contact_points` property does not contain any port
  information. Those should be specified in `cassandra_port`. Thanks
  [Vermeille](https://github.com/Vermeille) for the contribution.
  [#2263](https://github.com/Mashape/kong/pull/2263)
- Prevent an upstream or legitimate internal error in the load balancing code
  from throwing a Lua-land error as well.
  [#2327](https://github.com/Mashape/kong/pull/2327)
- Plugins:
  - hmac: Better handling of invalid base64-encoded signatures. Previously Kong
    would return an HTTP 500 error. We now properly return HTTP 403 Forbidden.
    [#2283](https://github.com/Mashape/kong/pull/2283)
- Admin API:
  - Detect conflicts between SNI Objects in the `/snis` and `/certificates`
    endpoint.
    [#2285](https://github.com/Mashape/kong/pull/2285)
  - The "active targets" endpoint does not require a trailing slash anymore.
    [#2307](https://github.com/Mashape/kong/pull/2307)
  - Target Objects can now be deleted with their ID as well as their name. The
    endpoint becomes: `/upstreams/:name_or_id/targets/:target_or_id`.
    [#2304](https://github.com/Mashape/kong/pull/2304)
