## Title

kong.tools.public.rate-limiting - Clustered, performant rate limiting for Kong


## Overview ##

This library is designed to provide an efficient, scalable,
eventually-consistent sliding window rate limiting library. It relies on atomic
operations in shared ngx memory zones to track window counters within a given
node, periodically syncing this data to a central data store (Cassandra,
Postgres, Redis, etc).

A sliding window rate limiting implementation tracks the number of hits assigned
to a specific key (such as an IP address, Consumer, Credential, etc) within a
given time window, taking into account previous hit rates to smooth out a
calculated rate, while still providing a familiar windowing interface that
modern developers are used to (e.g., *n* hits per second/minute/hour). This is
similar to a fixed window implementation, in which request rates reset at the
beginning of the window, but without the "reset bump" from which fixed window
implementations suffer, while providing a more intuitive interface beyond what
leaky bucket or token bucket implementations can offer.

A sliding window takes into account a weighted value of the previous window when
calculating the current rate for a given key. A window is defined as a period of
time, starting at a given "floor" timestamp, where the floor is calculated based
on the size of the window. For window sizes of 60 seconds, the floor always
falls at the *0th* second (e.g., at the beginning of any given minute).
Likewise, windows with a size of 30 seconds will begin at the *0th* and *30th*
seconds of each minute.

Consider a rate limit of 10 hits per minute. In this configuration, this library
will calculate the hit rate of a given key based on the number of hits for
the current window (starting at the beginning of the current minute), and a
weighted percentage of all hits of the previous window (e.g., the previous
minute). This weight is calculated based on the current timestamp with respect
to the window size in question; the farther away the current time is from the
start of the previous window, the lower the weight percentage. This value is
best expressed through an example:

```
current window rate: 10
previous window rate: 20
window size: 60
current time position: 30 (seconds past the start of the current window)
weight = .5 (60 second window size - 30 seconds past the window start)

rate = 'current rate' + 'previous_weight' * 'weight'
     = 10             + 20                * ('window size' - 'window position') / 'window_size'
     = 10             + 20                * (60 - 30) / 60
     = 10             + 20                * .5
     = 20
```

Strictly speaking, the formula used to define the weighting percentage is as
follows:

`weight = (window_size - (time() % window_size)) / window_size`

Where `time()` is the value of the current Unix timestamp.

In addition to sliding window calculations, this library can also be used to
provide a fixed window rate limiting implementation. By design, fixed window
and sliding window calculations are very similar. A fixed window calculation
simply ignores the value of the previous window. An alternative way to imagine
this is that, in fixed window calculations, the `weight` associated with the
previous window is always `0`.

Each node in the Kong cluster relies on its own in-memory data store as the
source of truth for rate limiting counters. Periodically, each node pushes a
counter increment for each key it saw to the cluster, which is expected to
atomically apply this diff to the appropriate key. The node then retrieves this
key's value from the data store, along with other relevant keys for this data
sync cycle. In this manner, each node shares the relevant portions of data with
the cluster, while relying on a very high-performance method of tracking data
during each request. This cycle of converge -> diverge -> reconverge among nodes
in the cluster provides our eventually-consistent model.

The periodic rate at which nodes converge is configurable; shorter sync
intervals will result in less divergence of data points when traffic is spread
across multiple nodes in the cluster (e.g., when sitting behind a round robin
balancer), whereas longer sync intervals put less r/w pressure on the datastore,
and less overhead on each node to calculate diffs and fetch new synced values.

In addition to periodic data sync behavior, this library can implement rate
limiting counter in a synchronous pattern by defining its `sync_rate` as `0`. In
such a case, the given counter will be applied directly to the datastore. This
library can also forgo syncing counter data entirely, and only apply incremental
counters to its local memory zone, by defining a `sync_rate` value of less than
`0`.

Module configuration data, such as sync rate, shared dictionary name, storage
policy, etc, is kept in a per-worker public configuration table. Multiple
configurations can be defined as stored as arbitrary `namespaces` (more on this
below).


## Developer Notes

### Public Functions

The following public functions are provided by this library:


#### ratelimiting.new_instance

*syntax: ratelimiting = ratelimiting.new_instance(instance_name)*

Previously this library used a module level global table `config` and thus
lacked of necessary data isolation between different plugins. So when two or
more different plugins are using it at the same time, it doesn't work normally
because we can't distinguish which namespaces belong to which plugin. When the
`reconfigure` event happens, the plugin will delete all the namespaces it does
not use anymore, but those deleted namespaces may belong to other plugins.

To provide necessary isolation without changing the original interfaces, we
added this new interface. Every returned instance has its own
`ratelimiting.config` that won't interfere with each other. As a usage example:
`local ratelimiting = require("kong.tools.public.rate-limiting").new_instance("rate-limiting-foo")`

If the library is used in the old way, the behavior is as before. In this case,
it will return a default instance which may be shared with other plugins.
`local ratelimiting = require("kong.tools.public.rate-limiting")`

Other functions below remain unchanged.

#### ratelimiting.new

*syntax: ok = ratelimiting.new(opts)*

Define configurations for a new namespace. The following options are accepted:
- dict: Name of the shared dictionary to use
- sync_rate: Rate, in seconds, to sync data diffs to the storage server.
- strategy: Storage strategy to use. currently `cassandra`, `postgres`, and
    `redis` are supported. Strategies must provide several public functions
    defined below.
- strategy_opts: A table of options used by the storage strategy. Currently only
    applicable for the 'redis' strategy.
- namespace: String defining these config values. A namespace may only be
    defined once; if a namespace has already been defined on this worker,
    an error is thrown. If no namespace is defined, the literal string "default"
    will be used.
- window_sizes: A list of window sizes used by this configuration.


#### ratelimiting.increment

*syntax: rate = ratelimiting.increment(key, window_size, value, namespace?, weight?)*

Increment a given key for window_size by value. If `namespace` is undefined, the
"default" namespace is used. `value` can be any number Lua type (but ensure that
the storage strategy in use for this namespace can support decimal values if
a non-integer value is provided). This function returns the sliding rate for
this key/window_size after the increment of value has been applied.


#### ratelimit.sliding_window

*syntax: rate = ratelimit.sliding_window(key, window_size, cur_diff?, namespace?, weight?)*

Return the current sliding rate for this key/window_size. An optional `cur_diff`
value can be provided that overrides the current stored diff for this key.
If `namespace` is undefined, the "default" namespace is used.


#### ratelimiting.sync

*syntax: ratelimiting.sync(premature, namespace?)*

sSnc all currently stored key diffs in this worker with the storage server, and
retrieve the newly synced value. If `namespace` is undefined, the "default"
namespace is used. Before the diffs are pushed, another sync call for the given
namespace is scheduled at `sync_rate` seconds in the future. Given this, this
function should typically be called during the `init_worker` phase to initialize
the recurring timer. This function is intended to be called in an `ngx.timer`
context; hence, the first variable represents the injected `premature` param.


#### ratelimiting.fetch

*syntax: ratelimiting.fetch(premature, namespace, time, timeout?)*

Retrieve all relevent counters for the given namespace at the given time. This
function establishes a shm mutex such that only one worker will fetch and
populate the shm per execution. If timeout is defined, the mutex will expire
based on the given timeout value; otherwise, the mutex is unlocked immediately
following the dictionary update. This function can be called in an `ngx.timer`
context; hence, the first variable represents the injected `premature` param.


### Strategy Functions

Storage strategies must provide the following interfaces:


#### strategy_class.new

*syntax: strategy = strategy_class.new(dao_factory, opts)*

Implement a new strategy object. `opts` is expected to be a table type, and can
be used to pass opaque/arbitrary options to the strategy class.


#### strategy:push_diffs

*syntax: ok, err = strategy:push_diffs(diffs)*

Push a table of key diffs to the storage server. `diffs` is a table provided
in the following format:

```
  [1] = {
    key = "1.2.3.4",
    windows = {
      {
        window    = 12345610,
        size      = 60,
        diff      = 5,
        namespace = foo,
      },
      {
        window    = 12345670,
        size      = 60,
        diff      = 5,
        namespace = foo,
      },
    }
  },
  ...
  ["1.2.3.4"] = 1,
  ...
```

Returns error if failed to push diffs to the strategy.

#### strategy:get_counters

*syntax: rows, err = strategy:get_counters(namespace, window_sizes, time?)*

Return an iterator for each key stored in the datastore/redis for a given
`namepsace` and list of window sizes. 'time' is an optional unix second-
precision timestamp; if not provided, this value will be set via `ngx.time()`.
It is encouraged to pass this via a previous defined timestamp, depending
on the context (e.g., if previous calls in the same thread took a nontrivial
amount of time to run).

Returns error if failed to get counters from the strategy.

#### strategy:get_window

*syntax: window, err = strategy:get_window(key, namespace, window_start, window_size)*

Retrieve a single key from the data store based on the values provided. Returns errors
if failed to get values from the strategy.
