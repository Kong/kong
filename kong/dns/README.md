Name
====

Kong DNS client - The module is currently only used by Kong, and builds on top of the `lua-resty-dns` and `lua-resty-mlcache` libraries.

Table of Contents
=================

* [Name](#name)
* [APIs](#apis)
    * [new](#new)
    * [resolve](#resolve)
    * [resolve_address](#resolve_address)
* [Performance characteristics](#performance-characteristics)
    * [Memory](#memory)

# APIs

The following APIs are for internal development use only within Kong. In the current version, the new DNS library still needs to be compatible with the original DNS library. Therefore, the functions listed below cannot be directly invoked. For example, the `_M:resolve` function in the following APIs will be replaced to ensure compatibility with the previous DNS library API interface specifications `_M.resolve`.

## new

**syntax:** *c, err = dns_client.new(opts)*  
**context:** any

**Functionality:**

Creates a dns client object. Returns `nil` and a message string on error.

Performs a series of initialization operations:

* parse `host` file,
* parse `resolv.conf` file (used by the underlying `lua-resty-dns` library),
* initialize multiple TTL options,
* create a mlcache object and initialize it.

**Input parameters:**

`@opts` It accepts a options table argument. The following options are supported:

* TTL options:
  * `valid_ttl`: (default: `nil`)
    * By default, it caches answers using the TTL value of a response. This optional parameter (in seconds) allows overriding it.
  * `stale_ttl`: (default: `3600`)
    * the time in seconds for keeping expired DNS records.
    * Stale data remains in use from when a record expires until either the background refresh query completes or until `stale_ttl` seconds have passed. This helps Kong stay resilient if the DNS server is temporarily unavailable.
  * `error_ttl`: (default: `1`)
    * the time in seconds for caching DNS error responses.
* `hosts`: (default: `/etc/hosts`)
  * the path of `hosts` file.
* `resolv_conf`: (default: `/etc/resolv.conf`)
  * the path of `resolv.conf` file, it will be parsed and passed into the underlying `lua-resty-dns` library.
* `family`: (default: `{ "SRV", "A", "AAAA" }`)
  * the types of DNS records that the library should query, it is taken from `kong.conf` option `dns_family`.
* options for the underlying `lua-resty-dns` library:
  * `retrans`: (default: `5`)
    * the total number of times of retransmitting the DNS request when receiving a DNS response times out according to the timeout setting. When trying to retransmit the query, the next nameserver according to the round-robin algorithm will be picked up.
    * If not given, it is taken from `resolv.conf` option `options attempts:<value>`.
  * `timeout`: (default: `2000`)
    * the time in milliseconds for waiting for the response for a single attempt of request transmission.
    * If not given, it is taken from `resolv.conf` option `options timeout:<value>`. But note that its unit in `resolv.conf` is second.
  * `random_resolver`: (default: `false`)
    * a boolean flag controls whether to randomly pick the nameserver to query first. If `true`, it will always start with the random nameserver.
    * If not given, it is taken from `resolv.conf` option `rotate`.
  * `nameservers`:
    * a list of nameservers to be used. Each nameserver entry can be either a single hostname string or a table holding both the hostname string and the port number. For example, `{"8.8.8.8", {"8.8.4.4", 53} }`.
    * If not given, it is taken from `resolv.conf` option `nameserver`.
* `cache_purge`: (default: `false`)
  * a boolean flag controls whether to clear the internal cache shared by other DNS client instances across workers.

[Back to TOC](#table-of-contents)

## resolve

**syntax:** *answers, err, tries? = resolve(qname, qtype, cache_only, tries?)*  
**context:** *rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, ngx.timer.\**

**Functionality:**

Performs a DNS resolution.

1. Check if the `<qname>` matches SRV format (`\_service.\_proto.name`) to determine the `<qtype>` (SRV or A/AAAA), then use the key `<qname>:<qtype>` to query mlcache. If cached results are found, return them directly.
2. If there are no results available in the cache, it triggers the L3 callback of `mlcache:get` to query records from the DNS servers, details are as follows:
    1. Check if `<qname>` has an IP address in the `hosts` file, return if found.
    2. Check if `<qname>` is an IP address itself, return if true.
    3. Use `mlcache:peek` to check if the expired key still exists in the shared dictionary. If it does, return it directly to mlcache and trigger an asynchronous background task to update the expired data (`start_stale_update_task`). The maximum time that expired data can be reused is `stale_ttl`, but the maximum TTL returned to mlcache cannot exceed 60s. This way, if the expired key is not successfully updated by the background task after 60s, it can still be reused by calling the `resolve` function from the upper layer to trigger the L3 callback to continue executing this logic and initiate another background task for updating.
        1. For example, with a `stale_ttl` of 3600s, if the background task fails to update the record due to network issues during this time, and the upper-level application continues to call resolve to get the domain name result, it will trigger a background task to query the DNS result for that domain name every 60s, resulting in approximately 60 background tasks being triggered (3600s/60s).
    4. Query the DNS server, with `<qname>:<qtype>` combinations:
            1. The `<qname>` is extended according to settings in `resolv.conf`, such as `ndots`, `search`, and `domain`.

**Return value:**

* Return value `answers, err`:
  * Return one array-like Lua table contains all the records.
    * For example, `{{"address":"[2001:db8:3333:4444:5555:6666:7777:8888]","class":1,"name":"example.test","ttl":30,"type":28},{"address":"192.168.1.1","class":1,"name":"example.test","ttl":30,"type":1},"expire":1720765379,"ttl":30}`.
      * IPv6 addresses are enclosed in brackets (`[]`).
  * If the server returns a non-zero error code, it will return `nil` and a string describing the error in this record.
    * For example, `nil, "dns server error: name error"`, the server returned a result with error code 3 (NXDOMAIN).
  * In case of severe errors, such network error or server's malformed DNS record response, it will return `nil` and a string describing the error instead. For example:
      * `nil, "dns server error: failed to send request to UDP server 10.0.0.1:53: timeout"`, there was a network issue.
* Return value and input parameter `@tries?`:
  * If provided as an empty table, it will be returned as a third result. This table will be an array containing the error message for each (if any) failed try.
    * For example, `[["example.test:A","dns server error: 3 name error"], ["example.test:AAAA","dns server error: 3 name error"]]`, both attempts failed due to a DNS server error with error code 3 (NXDOMAIN), indicating a name error.

**Input parameters:**

* `@qname`: the domain name to resolve.
* `@qtype`: (optional: `nil` or DNS TYPE value)
  * specify the query type instead of `self.order` types.
* `@cache_only`: (optional: `boolean`)
  * control whether to solely retrieve data from the internal cache without querying to the nameserver.
* `@tries?`: see the above section `Return value and input paramter @tries?`.

[Back to TOC](#table-of-contents)

## resolve_address

**syntax:** *ip, port_or_err, tries? = resolve_address(name, port, cache_only, tries?)*  
**context:** *rewrite_by_lua\*, access_by_lua\*, content_by_lua\*, ngx.timer.\**

**Functionality:**

Performs a DNS resolution, and return a single randomly selected address (IP and port number).

When calling multiple times on cached records, it will apply load-balancing based on a round-robin (RR) scheme. For SRV records, this will be a _weighted_ round-robin (WRR) scheme (because of the weights it will be randomized). It will apply the round-robin schemes on each level individually.

**Return value:**

* Return value `ip, port_or_err`:
  * Return one IP address and port number from records.
  * Return `nil, err` if errors occur, with `err` containing an error message.
* Return value and input parameter `@tries?`: same as `@tries?` of `resolve` API.

**Input parameters:**

* `@name`: the domain name to resolve.
* `@port`: (optional: `nil` or port number)
  * default port number to return if none was found in the lookup chain (only SRV records carry port information, SRV with `port=0` will be ignored).
* `@cache_only`: (optional: `boolean`)
  * control whether to solely retrieve data from the internal cache without querying to the nameserver.

[Back to TOC](#table-of-contents)

# Performance characteristics

## Memory

We evaluated the capacity of DNS records using the following resources:

* Shared memory size:
  * 5 MB (by default): `lua_shared_dict kong_dns_cache 5m`.
  * 10 MB: `lua_shared_dict kong_dns_cache 10m`.
* DNS response:
  * Each DNS resolution response contains some number of A type records.
    * Record: ~80 bytes json string, e.g., `{address = "127.0.0.1", name = <domain>, ttl = 3600, class = 1, type = 1}`.
  * Domain: ~36 bytes string, e.g., `example<n>.long.long.long.long.test`. Domain names with lengths between 10 and 36 bytes yield similar results.

The results of evaluation are as follows:

| shared memory size | number of records per response | number of loaded responses |
|--------------------|-------------------|----------|
| 5 MB               | 1                 | 20224    |
| 5 MB               | 2 ~ 3             | 10081    |
| 5 MB               | 4 ~ 9             | 5041     |
| 5 MB               | 10 ~ 20           | 5041     |
| 5 MB               | 21 ~ 32           | 1261     |
| 10 MB              | 1                 | 40704    |
| 10 MB              | 2 ~ 3             | 20321    |
| 10 MB              | 4 ~ 9             | 10161    |
| 10 MB              | 10 ~ 20           | 5081     |
| 10 MB              | 20 ~ 32           | 2541     |


[Back to TOC](#table-of-contents)
