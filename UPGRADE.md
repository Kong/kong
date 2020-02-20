This document guides you through the process of upgrading Kong. First, check if
a section named "Upgrade to `x.x.x`" exists, with `x.x.x` being the version
you are planning to upgrade to. If such a section does not exist, the upgrade
you want to perform does not have any particular instructions, and you can
simply consult the [Suggested upgrade path](#suggested-upgrade-path).

## Suggested upgrade path

Unless indicated otherwise in one of the upgrade paths of this document, it is
possible to upgrade Kong **without downtime**:

Assuming that Kong is already running on your system, acquire the latest
version from any of the available [installation
methods](https://getkong.org/install/) and proceed to install it, overriding
your previous installation.

If you are planning to make modifications to your configuration, this is a
good time to do so.

Then, run migration to upgrade your database schema:

```shell
$ kong migrations up [-c configuration_file]
```

If the command is successful, and no migration ran
(no output), then you only have to
[reload](https://docs.konghq.com/1.0.x/cli/#kong-reload) Kong:

```shell
$ kong reload [-c configuration_file]
```

**Reminder**: `kong reload` leverages the Nginx `reload` signal that seamlessly
starts new workers, which take over from old workers before those old workers
are terminated. In this way, Kong will serve new requests via the new
configuration, without dropping existing in-flight connections.


## Upgrade to `2.0.0`

Kong adheres to [semantic versioning](https://semver.org/), which makes a
distinction between "major", "minor" and "patch" versions. The upgrade path
will be different on which previous version from which you are migrating.
Upgrading into 2.0.x is a major version upgrade, so be aware of any
breaking changes listed in the [CHANGELOG.md](https://github.com/Kong/kong/blob/2.0.0/CHANGELOG.md) document.


#### 1. Dependencies

If you are using the provided binary packages, all necessary dependencies
are bundled and you can skip this section.

If you are building your dependencies by hand, there are changes since the
previous release, so you will need to rebuild them with the latest patches.

The required OpenResty version is
[1.15.8.2](http://openresty.org/en/changelog-1015008.html), and the
the set of [OpenResty
patches](https://github.com/Kong/kong-build-tools/tree/master/openresty-build-tools/openresty-patches)
included has changed, including the latest release of
[lua-kong-nginx-module](https://github.com/Kong/lua-kong-nginx-module).
Our [kong-build-tools](https://github.com/Kong/kong-build-tools)
repository allows you to build OpenResty with the necessary patches
and modules easily.

For Go support, you also need the [Kong go-pluginserver](https://github.com/kong/go-pluginserver).
This is bundled with Kong binary packages and it is automatically started by
Kong if Go plugin support is enabled in Kong's configuration.
Note that the Go version used to compile any Go plugins needs to match the Go
version of the `go-pluginserver`. You can check the Go version used to
build the `go-pluginserver` binary running `go-pluginserver -version`.


#### 2. Breaking Changes

Kong 2.0.0 does include a few breaking changes over Kong 1.x, all of them
related to the removal of service mesh:

- **Removed Service Mesh support** - That has been deprecated in Kong 1.4
  and made off-by-default already, and the code is now be gone in 2.0.
  For Service Mesh, we now have [Kuma](https://kuma.io), which is something
  designed for Mesh patterns from day one, so we feel at peace with removing
  Kong's native Service Mesh functionality and focus on its core capabilities
  as a gateway.
- As part of service mesh removal, serviceless proxying was removed.
  You can still set `service = null` when creating a route for use with
  serverless plugins such as `aws-lambda`, or `request-termination`.
- Removed the `origins` property.
- Removed the `transparent` property.
- Removed the Sidecar Injector plugin which was used for service mesh.
- The **Nginx configuration file has changed**, which means that you need to update
  it if you are using a custom template. Changes were made to improve
  stream mode support and to make the Nginx injections system more
  powerful so that custom templates are less of a necessity. The changes
  are detailed in a diff included below.
  - :warning: Note that the `kong_cache` shm was split into two
    shms: `kong_core_cache` and `kong_cache`. If you are using a
    custom Nginx template, make sure core cache shared dictionaries
    are defined, including db-less mode shadow definitions.
    Both cache values rely on the already existent `mem_cache_size`
    configuration option to set their size, so when upgrading from
    a previous Kong version, the cache memory consumption might
    double if this value is not adjusted.

<details>
<summary><strong>Click here to see the Nginx configuration changes</strong></summary>
<p>

```diff
diff --git a/kong/templates/nginx_kong.lua b/kong/templates/nginx_kong.lua
index 5c6c1db03..6b4b4a818 100644
--- a/kong/templates/nginx_kong.lua
+++ b/kong/templates/nginx_kong.lua
@@ -5,52 +5,46 @@ server_tokens off;
 > if anonymous_reports then
 ${{SYSLOG_REPORTS}}
 > end
-
 error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

-> if nginx_optimizations then
->-- send_timeout 60s;          # default value
->-- keepalive_timeout 75s;     # default value
->-- client_body_timeout 60s;   # default value
->-- client_header_timeout 60s; # default value
->-- tcp_nopush on;             # disabled until benchmarked
->-- proxy_buffer_size 128k;    # disabled until benchmarked
->-- proxy_buffers 4 256k;      # disabled until benchmarked
->-- proxy_busy_buffers_size 256k; # disabled until benchmarked
->-- reset_timedout_connection on; # disabled until benchmarked
-> end
-
-client_max_body_size ${{CLIENT_MAX_BODY_SIZE}};
-proxy_ssl_server_name on;
-underscores_in_headers on;
-
 lua_package_path       '${{LUA_PACKAGE_PATH}};;';
 lua_package_cpath      '${{LUA_PACKAGE_CPATH}};;';
 lua_socket_pool_size   ${{LUA_SOCKET_POOL_SIZE}};
+lua_socket_log_errors  off;
 lua_max_running_timers 4096;
 lua_max_pending_timers 16384;
+lua_ssl_verify_depth   ${{LUA_SSL_VERIFY_DEPTH}};
+> if lua_ssl_trusted_certificate then
+lua_ssl_trusted_certificate '${{LUA_SSL_TRUSTED_CERTIFICATE}}';
+> end
+
 lua_shared_dict kong                        5m;
+lua_shared_dict kong_locks                  8m;
+lua_shared_dict kong_healthchecks           5m;
+lua_shared_dict kong_process_events         5m;
+lua_shared_dict kong_cluster_events         5m;
+lua_shared_dict kong_rate_limiting_counters 12m;
+lua_shared_dict kong_core_db_cache          ${{MEM_CACHE_SIZE}};
+lua_shared_dict kong_core_db_cache_miss     12m;
 lua_shared_dict kong_db_cache               ${{MEM_CACHE_SIZE}};
-> if database == "off" then
-lua_shared_dict kong_db_cache_2     ${{MEM_CACHE_SIZE}};
-> end
 lua_shared_dict kong_db_cache_miss          12m;
 > if database == "off" then
+lua_shared_dict kong_core_db_cache_2        ${{MEM_CACHE_SIZE}};
+lua_shared_dict kong_core_db_cache_miss_2   12m;
+lua_shared_dict kong_db_cache_2             ${{MEM_CACHE_SIZE}};
 lua_shared_dict kong_db_cache_miss_2        12m;
 > end
-lua_shared_dict kong_locks          8m;
-lua_shared_dict kong_process_events 5m;
-lua_shared_dict kong_cluster_events 5m;
-lua_shared_dict kong_healthchecks   5m;
-lua_shared_dict kong_rate_limiting_counters 12m;
 > if database == "cassandra" then
 lua_shared_dict kong_cassandra              5m;
 > end
-lua_socket_log_errors off;
-> if lua_ssl_trusted_certificate then
-lua_ssl_trusted_certificate '${{LUA_SSL_TRUSTED_CERTIFICATE}}';
+> if role == "control_plane" then
+lua_shared_dict kong_clustering             5m;
+> end
+
+underscores_in_headers on;
+> if ssl_ciphers then
+ssl_ciphers ${{SSL_CIPHERS}};
 > end
-lua_ssl_verify_depth ${{LUA_SSL_VERIFY_DEPTH}};

 # injected nginx_http_* directives
 > for _, el in ipairs(nginx_http_directives) do
@@ -66,61 +60,47 @@ init_worker_by_lua_block {
     Kong.init_worker()
 }

-
-> if #proxy_listeners > 0 then
+> if (role == "traditional" or role == "data_plane") and #proxy_listeners > 0 then
 upstream kong_upstream {
     server 0.0.0.1;
     balancer_by_lua_block {
         Kong.balancer()
     }

-# injected nginx_http_upstream_* directives
-> for _, el in ipairs(nginx_http_upstream_directives) do
+    # injected nginx_upstream_* directives
+> for _, el in ipairs(nginx_upstream_directives) do
     $(el.name) $(el.value);
 > end
 }

 server {
     server_name kong;
-> for i = 1, #proxy_listeners do
-    listen $(proxy_listeners[i].listener);
+> for _, entry in ipairs(proxy_listeners) do
+    listen $(entry.listener);
 > end
+
     error_page 400 404 408 411 412 413 414 417 494 /kong_error_handler;
     error_page 500 502 503 504                     /kong_error_handler;

     access_log ${{PROXY_ACCESS_LOG}};
     error_log  ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

-    client_body_buffer_size ${{CLIENT_BODY_BUFFER_SIZE}};
-
 > if proxy_ssl_enabled then
     ssl_certificate     ${{SSL_CERT}};
     ssl_certificate_key ${{SSL_CERT_KEY}};
+    ssl_session_cache   shared:SSL:10m;
     ssl_certificate_by_lua_block {
         Kong.ssl_certificate()
     }
-
-    ssl_session_cache shared:SSL:10m;
-    ssl_session_timeout 10m;
-    ssl_prefer_server_ciphers on;
-    ssl_ciphers ${{SSL_CIPHERS}};
-> end
-
-> if client_ssl then
-    proxy_ssl_certificate ${{CLIENT_SSL_CERT}};
-    proxy_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
-> end
-
-    real_ip_header     ${{REAL_IP_HEADER}};
-    real_ip_recursive  ${{REAL_IP_RECURSIVE}};
-> for i = 1, #trusted_ips do
-    set_real_ip_from   $(trusted_ips[i]);
 > end

     # injected nginx_proxy_* directives
 > for _, el in ipairs(nginx_proxy_directives) do
     $(el.name) $(el.value);
 > end
+> for i = 1, #trusted_ips do
+    set_real_ip_from  $(trusted_ips[i]);
+> end

     rewrite_by_lua_block {
         Kong.rewrite()
@@ -171,43 +151,93 @@ server {
         proxy_pass_header     Server;
         proxy_pass_header     Date;
         proxy_ssl_name        $upstream_host;
+        proxy_ssl_server_name on;
+> if client_ssl then
+        proxy_ssl_certificate ${{CLIENT_SSL_CERT}};
+        proxy_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
+> end
         proxy_pass            $upstream_scheme://kong_upstream$upstream_uri;
     }

     location @grpc {
         internal;
+        default_type         '';
         set $kong_proxy_mode 'grpc';

+        grpc_set_header      TE                $upstream_te;
         grpc_set_header      Host              $upstream_host;
         grpc_set_header      X-Forwarded-For   $upstream_x_forwarded_for;
         grpc_set_header      X-Forwarded-Proto $upstream_x_forwarded_proto;
         grpc_set_header      X-Forwarded-Host  $upstream_x_forwarded_host;
         grpc_set_header      X-Forwarded-Port  $upstream_x_forwarded_port;
         grpc_set_header      X-Real-IP         $remote_addr;
-
+        grpc_pass_header     Server;
+        grpc_pass_header     Date;
         grpc_pass            grpc://kong_upstream;
     }

     location @grpcs {
         internal;
+        default_type         '';
         set $kong_proxy_mode 'grpc';

+        grpc_set_header      TE                $upstream_te;
         grpc_set_header      Host              $upstream_host;
         grpc_set_header      X-Forwarded-For   $upstream_x_forwarded_for;
         grpc_set_header      X-Forwarded-Proto $upstream_x_forwarded_proto;
         grpc_set_header      X-Forwarded-Host  $upstream_x_forwarded_host;
         grpc_set_header      X-Forwarded-Port  $upstream_x_forwarded_port;
         grpc_set_header      X-Real-IP         $remote_addr;
-
+        grpc_pass_header     Server;
+        grpc_pass_header     Date;
+        grpc_ssl_name        $upstream_host;
+        grpc_ssl_server_name on;
+> if client_ssl then
+        grpc_ssl_certificate ${{CLIENT_SSL_CERT}};
+        grpc_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
+> end
         grpc_pass            grpcs://kong_upstream;
     }

+    location = /kong_buffered_http {
+        internal;
+        default_type         '';
+        set $kong_proxy_mode 'http';
+
+        rewrite_by_lua_block       {;}
+        access_by_lua_block        {;}
+        header_filter_by_lua_block {;}
+        body_filter_by_lua_block   {;}
+        log_by_lua_block           {;}
+
+        proxy_http_version 1.1;
+        proxy_set_header      TE                $upstream_te;
+        proxy_set_header      Host              $upstream_host;
+        proxy_set_header      Upgrade           $upstream_upgrade;
+        proxy_set_header      Connection        $upstream_connection;
+        proxy_set_header      X-Forwarded-For   $upstream_x_forwarded_for;
+        proxy_set_header      X-Forwarded-Proto $upstream_x_forwarded_proto;
+        proxy_set_header      X-Forwarded-Host  $upstream_x_forwarded_host;
+        proxy_set_header      X-Forwarded-Port  $upstream_x_forwarded_port;
+        proxy_set_header      X-Real-IP         $remote_addr;
+        proxy_pass_header     Server;
+        proxy_pass_header     Date;
+        proxy_ssl_name        $upstream_host;
+        proxy_ssl_server_name on;
+> if client_ssl then
+        proxy_ssl_certificate ${{CLIENT_SSL_CERT}};
+        proxy_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
+> end
+        proxy_pass            $upstream_scheme://kong_upstream$upstream_uri;
+    }
+
     location = /kong_error_handler {
         internal;
+        default_type                 '';
+
         uninitialized_variable_warn  off;

         rewrite_by_lua_block {;}
-
         access_by_lua_block  {;}

         content_by_lua_block {
@@ -215,13 +245,13 @@ server {
         }
     }
 }
-> end
+> end -- (role == "traditional" or role == "data_plane") and #proxy_listeners > 0

-> if #admin_listeners > 0 then
+> if (role == "control_plane" or role == "traditional") and #admin_listeners > 0 then
 server {
     server_name kong_admin;
-> for i = 1, #admin_listeners do
-    listen $(admin_listeners[i].listener);
+> for _, entry in ipairs(admin_listeners) do
+    listen $(entry.listener);
 > end

     access_log ${{ADMIN_ACCESS_LOG}};
@@ -233,11 +263,7 @@ server {
 > if admin_ssl_enabled then
     ssl_certificate     ${{ADMIN_SSL_CERT}};
     ssl_certificate_key ${{ADMIN_SSL_CERT_KEY}};
-
-    ssl_session_cache shared:SSL:10m;
-    ssl_session_timeout 10m;
-    ssl_prefer_server_ciphers on;
-    ssl_ciphers ${{SSL_CIPHERS}};
+    ssl_session_cache   shared:AdminSSL:10m;
 > end

     # injected nginx_admin_* directives
@@ -265,20 +291,20 @@ server {
         return 200 'User-agent: *\nDisallow: /';
     }
 }
-> end
+> end -- (role == "control_plane" or role == "traditional") and #admin_listeners > 0

 > if #status_listeners > 0 then
 server {
     server_name kong_status;
-> for i = 1, #status_listeners do
-    listen $(status_listeners[i].listener);
+> for _, entry in ipairs(status_listeners) do
+    listen $(entry.listener);
 > end

     access_log ${{STATUS_ACCESS_LOG}};
     error_log  ${{STATUS_ERROR_LOG}} ${{LOG_LEVEL}};

-    # injected nginx_http_status_* directives
-> for _, el in ipairs(nginx_http_status_directives) do
+    # injected nginx_status_* directives
+> for _, el in ipairs(nginx_status_directives) do
     $(el.name) $(el.value);
 > end

@@ -303,4 +329,26 @@ server {
     }
 }
 > end
+
+> if role == "control_plane" then
+server {
+    server_name kong_cluster_listener;
+> for _, entry in ipairs(cluster_listeners) do
+    listen $(entry.listener) ssl;
+> end
+
+    access_log off;
+
+    ssl_verify_client   optional_no_ca;
+    ssl_certificate     ${{CLUSTER_CERT}};
+    ssl_certificate_key ${{CLUSTER_CERT_KEY}};
+    ssl_session_cache   shared:ClusterSSL:10m;
+
+    location = /v1/outlet {
+        content_by_lua_block {
+            Kong.serve_cluster_listener()
+        }
+    }
+}
+> end -- role == "control_plane"
 ]]
```

</p>
</details>


#### 3. Suggested Upgrade Path

##### Upgrade from `0.x` to `2.0.0`

The lowest version that Kong 2.0.0 supports migrating from is 1.0.0.
If you are migrating from a version lower than 0.14.1, you need to
migrate to 0.14.1 first. Then, once you are migrating from 0.14.1,
please migrate to 1.5.0 first.

The steps for upgrading from 0.14.1 to 1.5.0 are the same as upgrading
from 0.14.1 to Kong 1.0. Please follow the steps described in the
"Migration Steps from 0.14" in the [Suggested Upgrade Path for Kong
1.0](#kong-1-0-upgrade-path), with the addition of the `kong
migrations migrate-apis` command, which you can use to migrate legacy
`apis` configurations.

Once you migrated to 1.5.0, you can follow the instructions in the section
below to migrate to 2.0.0.

##### Upgrade from `1.0.0` - `1.5.0` to `2.0.0`

Kong 2.0.0 supports a no-downtime migration model. This means that while the
migration is ongoing, you will have two Kong clusters running, sharing the
same database. (This is sometimes called the Blue/Green migration model.)

The migrations are designed so that there is no need to fully copy
the data, but this also means that they are designed in such a way so that
the new version of Kong is able to use the data as it is migrated, and to do
it in a way so that the old Kong cluster keeps working until it is finally
time to decommission it. For this reason, the full migration is now split into
two steps, which are performed via commands `kong migrations up` (which does
only non-destructive operations) and `kong migrations finish` (which puts the
database in the final expected state for Kong 2.0.0).

1. Download 2.0.0, and configure it to point to the same datastore
   as your old (1.0 to 1.5) cluster. Run `kong migrations up`.
2. Once that finishes running, both the old and new (2.0.0) clusters can now
   run simultaneously on the same datastore. Start provisioning
   2.0.0 nodes, but do not use their Admin API yet. If you need to
   perform Admin API requests, these should be made to the old cluster's nodes.
   The reason is to prevent the new cluster from generating data
   that is not understood by the old cluster.
3. Gradually divert traffic away from your old nodes, and into
   your 2.0.0 cluster. Monitor your traffic to make sure everything
   is going smoothly.
4. When your traffic is fully migrated to the 2.0.0 cluster,
   decommission your old nodes.
5. From your 2.0.0 cluster, run: `kong migrations finish`.
   From this point on, it will not be possible to start
   nodes in the old cluster pointing to the same datastore anymore. Only run
   this command when you are confident that your migration
   was successful. From now on, you can safely make Admin API
   requests to your 2.0.0 nodes.

##### Installing 2.0.0 on a Fresh Datastore

The following commands should be used to prepare a new 2.0.0 cluster from a
fresh datastore:

```
$ kong migrations bootstrap [-c config]
$ kong start [-c config]
```


## Upgrade to `1.5.0`

Kong adheres to [semantic versioning](https://semver.org/), which makes a
distinction between "major", "minor" and "patch" versions. The upgrade path
will be different on which previous version from which you are migrating.
If you are upgrading from 0.x, this is a major upgrade. If you are
upgrading from 1.0.x or 1.4.x, this is a minor upgrade. Both scenarios are
explained below.

#### 1. Dependencies

If you are using the provided binary packages, all necessary dependencies
are bundled. If you are building your dependencies by hand, since Kong 1.4.0 the
only dependency upgraded is
[lua-resty-healthcheck](https://github.com/Kong/lua-resty-healthcheck) that must
be at least the 1.1.2 version from now on. For any lower version you should
check the upgrade path for the correct dependencies.

#### 2. Breaking Changes

Kong 1.5.0 does not include any breaking changes over Kong 1.4, but Kong 1.3
included breaking changes in configuration and for routing in some edge-cases
over Kong 1.2, and Kong 1.0 included a number of breaking changes over Kong 0.x.
If you are upgrading from 1.2, please read the section on
[Kong 1.3 Breaking Changes](#kong-1-3-breaking-changes) carefully before
proceeding. If you are upgrading from 0.14,x, please read the section on
[Kong 1.0 Breaking Changes](#kong-1-0-breaking-changes) carefully before
proceeding.

#### 3. Suggested Upgrade Path

##### Upgrade from `0.x` to `1.5.0`

The lowest version that Kong 1.5.0 supports migrating from is 0.14.1. if you
are migrating from a previous 0.x release, please migrate to 0.14.1 first.

For upgrading from 0.14.1 to Kong 1.5.0, the steps for upgrading are the same
as upgrading from 0.14.1 to Kong 1.0. Please follow the steps described in the
"Migration Steps from 0.14" in the [Suggested Upgrade Path for Kong
1.0](#kong-1-0-upgrade-path).

##### Upgrade from `1.0.x` - `1.4.x` to `1.5.0`

Kong 1.5.0 supports a no-downtime migration model. This means that while the
migration is ongoing, you will have two Kong clusters running, sharing the
same database. (This is sometimes called the Blue/Green migration model.)

The migrations are designed so that there is no need to fully copy
the data, but this also means that they are designed in such a way so that
the new version of Kong is able to use the data as it is migrated, and to do
it in a way so that the old Kong cluster keeps working until it is finally
time to decommission it. For this reason, the full migration is now split into
two steps, which are performed via commands `kong migrations up` (which does
only non-destructive operations) and `kong migrations finish` (which puts the
database in the final expected state for Kong 1.5.0).

1. Download 1.5.0, and configure it to point to the same datastore
   as your old (1.0 to 1.4) cluster. Run `kong migrations up`.
2. Once that finishes running, both the old and new (1.5.0) clusters can now
   run simultaneously on the same datastore. Start provisioning
   1.5.0 nodes, but do not use their Admin API yet. If you need to
   perform Admin API requests, these should be made to the old cluster's nodes.
   The reason is to prevent the new cluster from generating data
   that is not understood by the old cluster.
3. Gradually divert traffic away from your old nodes, and into
   your 1.5.0 cluster. Monitor your traffic to make sure everything
   is going smoothly.
4. When your traffic is fully migrated to the 1.5.0 cluster,
   decommission your old nodes.
5. From your 1.5.0 cluster, run: `kong migrations finish`.
   From this point on, it will not be possible to start
   nodes in the old cluster pointing to the same datastore anymore. Only run
   this command when you are confident that your migration
   was successful. From now on, you can safely make Admin API
   requests to your 1.5.0 nodes.

##### Installing 1.5.0 on a Fresh Datastore

The following commands should be used to prepare a new 1.5.0 cluster from a
fresh datastore:

```
$ kong migrations bootstrap [-c config]
$ kong start [-c config]
```


## Upgrade to `1.4.0`

Kong adheres to [semantic versioning](https://semver.org/), which makes a
distinction between "major", "minor" and "patch" versions. The upgrade path
will be different on which previous version from which you are migrating.
If you are upgrading from 0.x, this is a major upgrade. If you are
upgrading from 1.0.x or 1.3.x, this is a minor upgrade. Both scenarios are
explained below.


#### 1. Dependencies

If you are using the provided binary packages, all necessary dependencies
are bundled. If you are building your dependencies by hand, there are no changes
in dependencies from 1.3.0, for any lower version you should check the upgrade
path for the correct dependencies.

#### 2. Breaking Changes

Kong 1.4.0 does not include any breaking changes over Kong 1.3, but Kong 1.3
included breaking changes in configuration and for routing in some edge-cases
over Kong 1.2, and Kong 1.0 included a number of breaking changes over Kong 0.x.
If you are upgrading from 1.2, please read the section on
[Kong 1.3 Breaking Changes](#kong-1-3-breaking-changes) carefully before
proceeding. If you are upgrading from 0.14,x, please read the section on
[Kong 1.0 Breaking Changes](#kong-1-0-breaking-changes) carefully before
proceeding.

#### 3. Suggested Upgrade Path

##### Upgrade from `0.x` to `1.4.0`

The lowest version that Kong 1.4.0 supports migrating from is 0.14.1. if you
are migrating from a previous 0.x release, please migrate to 0.14.1 first.

For upgrading from 0.14.1 to Kong 1.4.0, the steps for upgrading are the same
as upgrading from 0.14.1 to Kong 1.0. Please follow the steps described in the
"Migration Steps from 0.14" in the [Suggested Upgrade Path for Kong
1.0](#kong-1-0-upgrade-path).

##### Upgrade from `1.0.x` - `1.3.x` to `1.4.0`

Kong 1.4.0 supports a no-downtime migration model. This means that while the
migration is ongoing, you will have two Kong clusters running, sharing the
same database. (This is sometimes called the Blue/Green migration model.)

The migrations are designed so that there is no need to fully copy
the data, but this also means that they are designed in such a way so that
the new version of Kong is able to use the data as it is migrated, and to do
it in a way so that the old Kong cluster keeps working until it is finally
time to decommission it. For this reason, the full migration is now split into
two steps, which are performed via commands `kong migrations up` (which does
only non-destructive operations) and `kong migrations finish` (which puts the
database in the final expected state for Kong 1.4.0).

1. Download 1.4.0, and configure it to point to the same datastore
   as your old (1.0 to 1.3) cluster. Run `kong migrations up`.
2. Once that finishes running, both the old and new (1.4.0) clusters can now
   run simultaneously on the same datastore. Start provisioning
   1.4.0 nodes, but do not use their Admin API yet. If you need to
   perform Admin API requests, these should be made to the old cluster's nodes.
   The reason is to prevent the new cluster from generating data
   that is not understood by the old cluster.
3. Gradually divert traffic away from your old nodes, and into
   your 1.4.0 cluster. Monitor your traffic to make sure everything
   is going smoothly.
4. When your traffic is fully migrated to the 1.4.0 cluster,
   decommission your old nodes.
5. From your 1.4.0 cluster, run: `kong migrations finish`.
   From this point on, it will not be possible to start
   nodes in the old cluster pointing to the same datastore anymore. Only run
   this command when you are confident that your migration
   was successful. From now on, you can safely make Admin API
   requests to your 1.4.0 nodes.

##### Installing 1.4.0 on a Fresh Datastore

The following commands should be used to prepare a new 1.4.0 cluster from a
fresh datastore:

```
$ kong migrations bootstrap [-c config]
$ kong start [-c config]
```

## Upgrade to `1.3`

#### 1. Breaking Changes

##### Dependencies

If you are using the provided binary packages, all necessary dependencies
are bundled. If you are building your dependencies by hand, you should
be aware of the following changes:

- The required OpenResty version has been bumped to
  [1.15.8.1](http://openresty.org/en/changelog-1015008.html). If you are
  installing Kong from one of our distribution packages, you are not affected
  by this change.
- From this version on, the new
  [lua-kong-nginx-module](https://github.com/Kong/lua-kong-nginx-module) Nginx
  module is **required** to be built into OpenResty for Kong to function
  properly. If you are installing Kong from one of our distribution packages,
  you are not affected by this change.
  [openresty-build-tools#26](https://github.com/Kong/openresty-build-tools/pull/26)

**Note:** if you are not using one of our distribution packages and compiling
OpenResty from source, you must still apply Kong's [OpenResty
patches](https://github.com/kong/openresty-patches) (and, as highlighted above,
compile OpenResty with the new lua-kong-nginx-module). Our new
[openresty-build-tools](https://github.com/Kong/openresty-build-tools)
repository will allow you to do both easily.

##### Core

- Bugfixes in the router *may, in some edge-cases*, result in different Routes
  being matched. It was reported to us that the router behaved incorrectly in
  some cases when configuring wildcard Hosts and regex paths (e.g.
  [#3094](https://github.com/Kong/kong/issues/3094)). It may be so that you are
  subject to these bugs without realizing it. Please ensure that wildcard Hosts
  and regex paths Routes you have configured are matching as expected before
  upgrading.
  [9ca4dc0](https://github.com/Kong/kong/commit/9ca4dc09fdb12b340531be8e0f9d1560c48664d5)
  [2683b86](https://github.com/Kong/kong/commit/2683b86c2f7680238e3fe85da224d6f077e3425d)
  [6a03e1b](https://github.com/Kong/kong/commit/6a03e1bd95594716167ccac840ff3e892ed66215)
- Upstream connections are now only kept-alive for 100 requests or 60 seconds
  (idle) by default. Previously, upstream connections were not actively closed
  by Kong. This is a (non-breaking) change in behavior inherited from Nginx
  1.15, and configurable via new configuration properties.

##### Configuration

- The `upstream_keepalive` configuration property is deprecated, and replaced
  by the new `nginx_http_upstream_keepalive` property. Its behavior is almost
  identical, but the notable difference is that the latter leverages the
  [injected Nginx
  directives](https://konghq.com/blog/kong-ce-nginx-injected-directives/)
  feature added in Kong 0.14.0.
- The Nginx configuration file has changed, which means that you need to update
  it if you are using a custom template. Changes were made to address the
  `upstream_keepalive` change, the new gRPC support, and to make `ssl_protocols`
  load via injected directives. The changes are detailed in a diff
  included below.

<details>
<summary><strong>Click here to see the Nginx configuration changes</strong></summary>
<p>

```diff
diff --git a/kong/templates/nginx_kong.lua b/kong/templates/nginx_kong.lua
index 761376a07..5a957a1b7 100644
--- a/kong/templates/nginx_kong.lua
+++ b/kong/templates/nginx_kong.lua
@@ -72,8 +72,10 @@ upstream kong_upstream {
     balancer_by_lua_block {
         Kong.balancer()
     }
-> if upstream_keepalive > 0 then
-    keepalive ${{UPSTREAM_KEEPALIVE}};
+
+# injected nginx_http_upstream_* directives
+> for _, el in ipairs(nginx_http_upstream_directives) do
+    $(el.name) $(el.value);
 > end
 }

@@ -93,7 +95,6 @@ server {
 > if proxy_ssl_enabled then
     ssl_certificate ${{SSL_CERT}};
     ssl_certificate_key ${{SSL_CERT_KEY}};
-    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
     ssl_certificate_by_lua_block {
         Kong.ssl_certificate()
     }
@@ -120,6 +121,26 @@ server {
     $(el.name) $(el.value);
 > end

+    rewrite_by_lua_block {
+        Kong.rewrite()
+    }
+
+    access_by_lua_block {
+        Kong.access()
+    }
+
+    header_filter_by_lua_block {
+        Kong.header_filter()
+    }
+
+    body_filter_by_lua_block {
+        Kong.body_filter()
+    }
+
+    log_by_lua_block {
+        Kong.log()
+    }
+
     location / {
         default_type                     '';

@@ -134,14 +155,7 @@ server {
         set $upstream_x_forwarded_proto  '';
         set $upstream_x_forwarded_host   '';
         set $upstream_x_forwarded_port   '';
-
-        rewrite_by_lua_block {
-            Kong.rewrite()
-        }
-
-        access_by_lua_block {
-            Kong.access()
-        }
+        set $kong_proxy_mode             'http';

         proxy_http_version 1.1;
         proxy_set_header   TE                $upstream_te;
@@ -157,38 +171,32 @@ server {
         proxy_pass_header  Date;
         proxy_ssl_name     $upstream_host;
         proxy_pass         $upstream_scheme://kong_upstream$upstream_uri;
+    }

-        header_filter_by_lua_block {
-            Kong.header_filter()
-        }
+    location @grpc {
+        internal;

-        body_filter_by_lua_block {
-            Kong.body_filter()
-        }
+        set $kong_proxy_mode       'grpc';
+        grpc_pass grpc://kong_upstream;
+    }

-        log_by_lua_block {
-            Kong.log()
-        }
+    location @grpcs {
+        internal;
+
+        set $kong_proxy_mode       'grpcs';
+        grpc_pass grpcs://kong_upstream;
     }

     location = /kong_error_handler {
         internal;
         uninitialized_variable_warn off;

-        content_by_lua_block {
-            Kong.handle_error()
-        }
-
-        header_filter_by_lua_block {
-            Kong.header_filter()
-        }
+        rewrite_by_lua_block {;}

-        body_filter_by_lua_block {
-            Kong.body_filter()
-        }
+        access_by_lua_block {;}

-        log_by_lua_block {
-            Kong.log()
+        content_by_lua_block {
+            Kong.handle_error()
         }
     }
 }
@@ -210,7 +218,6 @@ server {
 > if admin_ssl_enabled then
     ssl_certificate ${{ADMIN_SSL_CERT}};
     ssl_certificate_key ${{ADMIN_SSL_CERT_KEY}};
-    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;

     ssl_session_cache shared:SSL:10m;
     ssl_session_timeout 10m;
```

</p>
</details>

#### 2. Suggested Upgrade Path

##### Upgrade from `0.x` to `1.3`

The lowest version that Kong 1.3 supports migrating from is 0.14.1. if you
are migrating from a previous 0.x release, please migrate to 0.14.1 first.

For upgrading from 0.14.1 to Kong 1.3, the steps for upgrading are the same as
upgrading from 0.14.1 to Kong 1.0. Please follow the steps described in the
"Migration Steps from 0.14" in the [Suggested Upgrade Path for Kong
1.0](#kong-1-0-upgrade-path).

##### Upgrade from `1.0.x` - `1.2.x` to `1.3`

Kong 1.3 supports the no-downtime migration model. This means that while the
migration is ongoing, you will have two Kong clusters running, sharing the
same database. (This is sometimes called the Blue/Green migration model.)

The migrations are designed so that there is no need to fully copy
the data, but this also means that they are designed in such a way so that
the new version of Kong is able to use the data as it is migrated, and to do
it in a way so that the old Kong cluster keeps working until it is finally
time to decommission it. For this reason, the full migration is now split into
two steps, which are performed via commands `kong migrations up` (which does
only non-destructive operations) and `kong migrations finish` (which puts the
database in the final expected state for Kong 1.2).

1. Download 1.3, and configure it to point to the same datastore as your old
   (1.0 - 1.2) cluster. Run `kong migrations up`.
2. Once that finishes running, both the old and new (1.3) clusters can now run
   simultaneously on the same datastore. Start provisioning 1.3 nodes, but do
   not use their Admin API yet. If you need to perform Admin API requests,
   these should be made to the old cluster's nodes.  The reason is to prevent
   the new cluster from generating data that is not understood by the old
   cluster.
3. Gradually divert traffic away from your old nodes, and into
   your 1.3 cluster. Monitor your traffic to make sure everything
   is going smoothly.
4. When your traffic is fully migrated to the 1.3 cluster, decommission your
   old nodes.
5. From your 1.3 cluster, run: `kong migrations finish`.  From this point on,
   it will not be possible to start nodes in the old cluster pointing to the
   same datastore anymore. Only run this command when you are confident that
   your migration was successful. From now on, you can safely make Admin API
   requests to your 1.3 nodes.

##### Installing 1.3 on a Fresh Datastore

The following commands should be used to prepare a new 1.3 cluster from a fresh
datastore:

```
$ kong migrations bootstrap [-c config]
$ kong start [-c config]
```



## Upgrade to `1.2`

Kong adheres to [semantic versioning](https://semver.org/), which makes a
distinction between "major", "minor" and "patch" versions. The upgrade path
will be different on which previous version from which you are migrating.
If you are upgrading from 0.x, this is a major upgrade. If you are
upgrading from 1.0.x or 1.1.x, this is a minor upgrade. Both scenarios are
explained below.


#### 1. Dependencies

If you are using the provided binary packages, all necessary dependencies
are bundled. If you are building your dependencies by hand, you should
be aware of the following changes:

- The required OpenResty version is 1.13.6.2, but for a full feature set,
  including stream routing and service mesh abilities with mutual TLS, you need
  Kong's [openresty-patches](https://github.com/kong/openresty-patches).
  Note that the set of patches was updated from 1.0 to 1.2.
- The minimum required OpenSSL version is 1.1.1. If you are building by hand,
  make sure all dependencies, including LuaRocks modules, are compiled using
  the same OpenSSL version. If you are installing Kong from one of our
  distribution packages, you are not affected by this change.

#### 2. Breaking Changes

Kong 1.2 does not include any breaking changes over Kong 1.0 or 1.1, but Kong 1.0
included a number of breaking changes over Kong 0.x. If you are upgrading
from 0.14,x, please read the section on
[Kong 1.0 Breaking Changes](#kong-1-0-breaking-changes) carefully before
proceeding.

#### 3. Suggested Upgrade Path

##### Upgrade from `0.x` to `1.2`

The lowest version that Kong 1.2 supports migrating from is 0.14.1. if you
are migrating from a previous 0.x release, please migrate to 0.14.1 first.

For upgrading from 0.14.1 to Kong 1.2, the steps for upgrading are the same as
upgrading from 0.14.1 to Kong 1.0. Please follow the steps described in the
"Migration Steps from 0.14" in the [Suggested Upgrade Path for Kong
1.0](#kong-1-0-upgrade-path).

##### Upgrade from `1.0.x` or `1.1.x` to `1.2`

Kong 1.2 supports a no-downtime migration model. This means that while the
migration is ongoing, you will have two Kong clusters running, sharing the
same database. (This is sometimes called the Blue/Green migration model.)

The migrations are designed so that there is no need to fully copy
the data, but this also means that they are designed in such a way so that
the new version of Kong is able to use the data as it is migrated, and to do
it in a way so that the old Kong cluster keeps working until it is finally
time to decommission it. For this reason, the full migration is now split into
two steps, which are performed via commands `kong migrations up` (which does
only non-destructive operations) and `kong migrations finish` (which puts the
database in the final expected state for Kong 1.2).

1. Download 1.2, and configure it to point to the same datastore
   as your old (1.0 or 1.1) cluster. Run `kong migrations up`.
2. Once that finishes running, both the old and new (1.2) clusters can now
   run simultaneously on the same datastore. Start provisioning
   1.2 nodes, but do not use their Admin API yet. If you need to
   perform Admin API requests, these should be made to the old cluster's nodes.
   The reason is to prevent the new cluster from generating data
   that is not understood by the old cluster.
3. Gradually divert traffic away from your old nodes, and into
   your 1.2 cluster. Monitor your traffic to make sure everything
   is going smoothly.
4. When your traffic is fully migrated to the 1.2 cluster,
   decommission your old nodes.
5. From your 1.2 cluster, run: `kong migrations finish`.
   From this point on, it will not be possible to start
   nodes in the old cluster pointing to the same datastore anymore. Only run
   this command when you are confident that your migration
   was successful. From now on, you can safely make Admin API
   requests to your 1.2 nodes.

##### Upgrade Path from 1.2 Release Candidates

The process is the same as for upgrading from 1.0 listed above, but on step 1
you should run `kong migrations up --force` instead.

##### Installing 1.2 on a Fresh Datastore

The following commands should be used to prepare a new 1.2 cluster from a fresh datastore:

```
$ kong migrations bootstrap [-c config]
$ kong start [-c config]
```


## Upgrade to `1.1`

Kong adheres to [semantic versioning](https://semver.org/), which makes a
distinction between "major", "minor" and "patch" versions. The upgrade path
will be different on which previous version from which you are migrating.
If you are upgrading from 0.x, this is a major upgrade. If you are
upgrading from 1.0.x, this is a minor upgrade. Both scenarios are
explained below.


#### 1. Dependencies

If you are using the provided binary packages, all necessary dependencies
are bundled. If you are building your dependencies by hand, you should
be aware of the following changes:

- The required OpenResty version is 1.13.6.2, but for a full feature set,
  including stream routing and service mesh abilities with mutual TLS, you need
  Kong's [openresty-patches](https://github.com/kong/openresty-patches).
  Note that the set of patches was updated from 1.0 to 1.1.
- The minimum required OpenSSL version is 1.1.1. If you are building by hand,
  make sure all dependencies, including LuaRocks modules, are compiled using
  the same OpenSSL version. If you are installing Kong from one of our
  distribution packages, you are not affected by this change.

#### 2. Breaking Changes

Kong 1.1 does not include any breaking changes over Kong 1.0, but Kong 1.0
included a number of breaking changes over Kong 0.x. If you are upgrading
from 0.14,x, please read the section on
[Kong 1.0 Breaking Changes](#kong-1-0-breaking-changes) carefully before
proceeding.

#### 3. Suggested Upgrade Path

##### Upgrade from `0.x` to `1.1`

The lowest version that Kong 1.1 supports migrating from is 0.14.1. if you
are migrating from a previous 0.x release, please migrate to 0.14.1 first.

For upgrading from 0.14.1 to Kong 1.1, the steps for upgrading are the same as
upgrading from 0.14.1 to Kong 1.0. Please follow the steps described in the
"Migration Steps from 0.14" in the [Suggested Upgrade Path for Kong
1.0](#kong-1-0-upgrade-path).

##### Upgrade from `1.0.x` to `1.1`

Kong 1.1 supports a no-downtime migration model. This means that while the
migration is ongoing, you will have two Kong clusters running, sharing the
same database. (This is sometimes called the Blue/Green migration model.)

The migrations are designed so that there is no need to fully copy
the data, but this also means that they are designed in such a way so that
the new version of Kong is able to use the data as it is migrated, and to do
it in a way so that the old Kong cluster keeps working until it is finally
time to decommission it. For this reason, the full migration is now split into
two steps, which are performed via commands `kong migrations up` (which does
only non-destructive operations) and `kong migrations finish` (which puts the
database in the final expected state for Kong 1.1).

1. Download 1.1, and configure it to point to the same datastore
   as your 1.0 cluster. Run `kong migrations up`.
2. Once that finishes running, both 1.0 and 1.1 clusters can now
   run simultaneously on the same datastore. Start provisioning
   1.1 nodes, but do not use their Admin API yet. If you need to
   perform Admin API requests, these should be made to your 1.0 nodes.
   The reason is to prevent the new cluster from generating data
   that is not understood by the old cluster.
3. Gradually divert traffic away from your 1.0 nodes, and into
   your 1.1 cluster. Monitor your traffic to make sure everything
   is going smoothly.
4. When your traffic is fully migrated to the 1.1 cluster,
   decommission your 1.0 nodes.
5. From your 1.1 cluster, run: `kong migrations finish`.
   From this point on, it will not be possible to start 1.0
   nodes pointing to the same datastore anymore. Only run
   this command when you are confident that your migration
   was successful. From now on, you can safely make Admin API
   requests to your 1.1 nodes.

##### Upgrade Path from 1.1 Release Candidates

The process is the same as for upgrading from 1.0 listed above, but on step 1
you should run `kong migrations up --force` instead.

##### Installing 1.1 on a Fresh Datastore

The following commands should be used to prepare a new 1.1 cluster from a fresh datastore:

```
$ kong migrations bootstrap [-c config]
$ kong start [-c config]
```


## Upgrading `1.0.x` patch releases

If you are upgrading from another release in the 1.0.x series (e.g. from 1.0.0
to 1.0.1), there are no migrations. Simply upgrade your Kong installation and
[reload](https://docs.konghq.com/1.0.x/cli/#kong-reload) Kong:

```shell
$ kong reload [-c configuration_file]
```

If you are upgrading from 0.x, then read the following section for
detailed migration instructions.

## Upgrade from `0.x` to `1.0.x`

Kong 1.0 is a major upgrade, and includes a number of new features
as well as breaking changes.

This version introduces **a new schema format for plugins**, **changes in
Admin API endpoints**, **database migrations**, **Nginx configuration
changes**, and **removed configuration properties**.

In this release, the **API entity is removed**, along with its related
Admin API endpoints.

This section will highlight breaking changes that you need to be aware of
before upgrading and will describe the recommended upgrade path. We recommend
that you consult the full [1.0.0
Changelog](https://github.com/Kong/kong/blob/master/CHANGELOG.md) for a
complete list of changes and new features.

<a name="kong-1-0-breaking-changes"></a>
#### 1. Breaking Changes

##### Dependencies

- The required OpenResty version is 1.13.6.2, but for a full feature set,
  including stream routing and service mesh abilities with mutual TLS, you need
  Kong's [openresty-patches](https://github.com/kong/openresty-patches).
- The minimum required OpenSSL version is 1.1.1. If you are building by hand,
  make sure all dependencies, including LuaRocks modules, are compiled using
  the same OpenSSL version. If you are installing Kong from one of our
  distribution packages, you are not affected by this change.

##### Configuration

- The `custom_plugins` directive is removed (deprecated since 0.14.0).
  Use `plugins` instead, which you can use not only to enable
  custom plugins, but also to disable bundled plugins.
- The default value for `cassandra_lb_policy` changed from `RoundRobin`
  to `RequestRoundRobin`.
- The Nginx configuration file has changed, which means that you need to update
  it if you are using a custom template. The changes are detailed in a diff
  included below.

<details>
<summary><strong>Click here to see the Nginx configuration changes</strong></summary>
<p>

```diff
diff --git a/kong/templates/nginx_kong.lua b/kong/templates/nginx_kong.lua
index d4e416bc..8f268ffd 100644
--- a/kong/templates/nginx_kong.lua
+++ b/kong/templates/nginx_kong.lua
@@ -66,7 +66,9 @@ upstream kong_upstream {
     balancer_by_lua_block {
         Kong.balancer()
     }
+> if upstream_keepalive > 0 then
     keepalive ${{UPSTREAM_KEEPALIVE}};
+> end
 }

 server {
@@ -85,7 +87,7 @@ server {
 > if proxy_ssl_enabled then
     ssl_certificate ${{SSL_CERT}};
     ssl_certificate_key ${{SSL_CERT_KEY}};
-    ssl_protocols TLSv1.1 TLSv1.2;
+    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
     ssl_certificate_by_lua_block {
         Kong.ssl_certificate()
     }
@@ -200,7 +202,7 @@ server {
 > if admin_ssl_enabled then
     ssl_certificate ${{ADMIN_SSL_CERT}};
     ssl_certificate_key ${{ADMIN_SSL_CERT_KEY}};
-    ssl_protocols TLSv1.1 TLSv1.2;
+    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;

     ssl_session_cache shared:SSL:10m;
     ssl_session_timeout 10m;
```

</p>
</details>

- Kong generates a new template file for stream routing,
  `nginx-kong-stream.conf`, included in the `stream` block
  of its top-level Nginx configuration file. If you use
  a custom Nginx configuration and wish to use stream
  routing, you can generate this file using `kong prepare`.

##### Core

- The **API** entity and related concepts such as the
  `/apis` endpoint, are removed. These were deprecated since
  0.13.0. Instead, use **Routes** to configure your
  endpoints and **Services** to configure your upstream
  services.
- The old DAO implementation (`kong.dao`) is removed,
  which includes the old schema validation library. This
  has implications to plugin developers, listed below.
  - The last remaining entities that were converted to
    the new DAO implementation were Plugins, Upstreams
    and Targets. This has implications to the Admin API,
    listed below.

##### Plugins

Kong 1.0.0 marks the introduction of version 1.0.0 of
the Plugin Development Kit (PDK). No major changes are
made to the PDK compared to release 0.14, but some older
non-PDK functionality which was possibly used by custom
plugins is now removed.

- Plugins now use the new schema format introduced by the
  new DAO implementation, for both plugin schemas
  (in `schema.lua`) and custom DAO entities (`daos.lua`).
  To ease the transition of plugins, the plugin loader
  in 1.0 includes a *best-effort* schema auto-translator
  for `schema.lua`, which should be sufficient for many
  plugins (in 1.0.0rc1, our bundled plugins used the
  auto-translator; they now use the new format).
  - If your plugin using the old format in `schema.lua`
    fails to load, check the error logs for messages
    produced by the auto-translator. If a field cannot
    be auto-translated, you can make a gradual conversion
    of the schema file by adding a `new_type` entry to
    the field table translation of the format. See,
    for example, the [key-auth schema in 1.0.0rc1](https://github.com/Kong/kong/blob/1.0.0rc1/kong/plugins/key-auth/schema.lua#L39-L54).
    The `new_type` annotation is ignored by Kong 0.x.
  - If your custom plugin uses custom DAO objects (i.e.
    if it includes a `daos.lua` file), it needs to be
    converted to the new format. Their code also needs
    to be adjusted accordingly, replacing uses of
    `singletons.dao` or `kong.dao` by `kong.db` (note
    that this module exposes a different API from the
    old DAO implementation).
- Some Kong modules that had their functionality replaced
  by the PDK in 0.14.0 are now removed:
  - `kong.tools.ip`: use `kong.ip` from the PDK instead.
  - `kong.tools.public`: replaced by various functionalities
    of the PDK.
  - `kong.tools.responses`: use `kong.response.exit` from the PDK instead. You
    might want to use `kong.log.err` to log internal server errors as well.
- The `kong.api.crud_helpers` module was removed.
  Use `kong.api.endpoints` instead if you need to customize
  the auto-generated endpoints.

##### Admin API

- With the removal of the API entity, the `/apis` endpoint
  is removed; accordingly, other endpoints that accepted
  `api_id` no longer do so. Use Routes and Services instead.
- All entity endpoints now use the new Admin API implementation.
  This means their requests and responses now use the same
  syntax, which was already in use in endpoints such as
  `/routes` and `/services`.
  - All endpoints now use the same syntax for
    referencing other entities as `/routes`
    (for example, `"service":{"id":"..."}` instead of
    `"service_id":"..."`), both in requests and responses.
    - This change affects `/plugins` as well as
      plugin-specific endpoints.
  - Array-typed values are not specified as a
    comma-separated list anymore. It must be specified as a
    JSON array or using the various formats supported by
    the url-formencoded array notation of the new Admin API
    implementation (`a[1]=x&a[2]=y`, `a[]=x&a[]=y`,
    `a=x&a=y`).
    - This change affects attributes of the `/upstreams` endpoint.
  - Error responses for the updated endpoints use
    the new standardized format.
  - As a result of being moved to the new Admin API implementation,
    all endpoints supporting `PUT` do so with proper semantics.
  - See the [Admin API
    reference](https://docs.konghq.com/1.0.x/admin-api)
    for more details.

#### 2. Deprecation Notices

There are no deprecation notices in this release.

<a name="kong-1-0-upgrade-path"></a>
#### 3. Suggested Upgrade Path

##### Preliminary Checks

If your cluster is running a version lower than 0.14, you need to
upgrade to 0.14.1 first instead. Upgrading from a pre-0.14 cluster
straight to Kong 1.0 is **not** supported.

If you still use the deprecated API entity to configure your endpoints and
upstream services (via `/apis`) instead of using Routes for endpoints (via
`/routes`) and Services for upstream services (via `/services`), now is the
time to do so. Kong 1.0 will refuse to run migrations if you have any entity
configured using `/apis` in your datastore. Create equivalent Routes and
Services and delete your APIs. (Note that Kong does not do this automatically
because the naive option of creating a Route and Service pair for each API
would miss the point of the improvements brought by Routes and Services;
the ideal mapping of Routes and Services depends on your microservice
architecture.)

If you use additional plugins other than the ones bundled with Kong,
make sure they are compatible with Kong 1.0 prior to upgrading.
See the section above on Plugins for information on plugin compatibility.

##### Migration Steps from 0.14

Kong 1.0 introduces a new, improved migrations framework.
It supports a no-downtime, Blue/Green migration model for upgrading
from 0.14.x. This means that while the migration is ongoing, you will
have two Kong clusters running, sharing the same database. The "Blue" cluster
is your existing cluster running 0.14.x, the "Green" cluster is the new one
running Kong 1.0.

The migrations are designed so that there is no need to fully copy
the data, but this also means that they are designed in such a way so that
the new version of Kong is able to use the data as it is migrated, and to do
it in a way so that the old Kong cluster keeps working until it is finally
time to decommission it. For this reason, the full migration is now split into
two steps, which are performed via commands `kong migrations up` (which does
only non-destructive operations) and `kong migrations finish` (which puts the
database in the final expected state for Kong 1.0).

For a no-downtime migration from a 0.14 cluster to a 1.0 cluster,
we recommend the following sequence of steps:

1. Download 1.0, and configure it to point to the same datastore
   as your 0.14 cluster. Run `kong migrations up` from a Kong 1.0
   node.
2. Once that finishes running, both 0.14 and 1.0 clusters can now
   run simultaneously on the same datastore. Start provisioning
   1.0 nodes, but do not use their Admin API yet. If you need to
   perform Admin API requests, these should be made to your 0.14 nodes.
   The reason is to prevent the new cluster from generating data
   that is not understood by the old cluster.
3. Gradually divert traffic away from your 0.14 nodes, and into
   your 1.0 cluster. Monitor your traffic to make sure everything
   is going smoothly.
4. When your traffic is fully migrated to the 1.0 cluster,
   decommission your 0.14 nodes.
5. From your 1.0 cluster, run: `kong migrations finish`.
   From this point on, it will not be possible to start 0.14
   nodes pointing to the same datastore anymore. Only run
   this command when you are confident that your migration
   was successful. From now on, you can safely make Admin API
   requests to your 1.0 nodes.

##### Upgrade Path from 1.0 Release Candidates

The process is the same as for upgrading for 0.14 listed above, but on step 1 you should run `kong migrations up --force` instead.

##### Installing 1.0 on a Fresh Datastore

For installing on a fresh datastore, Kong 1.0 introduces the `kong migrations bootstrap` command. The following commands can be run to prepare a new 1.0 cluster from a fresh datastore:

```
$ kong migrations bootstrap [-c config]
$ kong start [-c config]
```


## Upgrade to `0.15`

This is the last release in the 0.x series, giving users one last chance to
upgrade while still using some of the options and concepts that were marked as
deprecated in Kong 0.x and were removed in Kong 1.0. Still, Kong 0.15 does
have a number of breaking changes related to functionality that has changed
since version 0.14.

This version introduces **a new schema format for plugins**, **changes in
Admin API endpoints**, **database migrations** and **Nginx configuration
changes**.

This section will highlight breaking changes that you need to be aware of
before upgrading and will describe the recommended upgrade path. We recommend
that you consult the full [0.15
Changelog](https://github.com/Kong/kong/blob/master/CHANGELOG.md) for a
complete list of changes and new features.

#### 1. Breaking Changes

##### Dependencies

- The required OpenResty version is 1.13.6.2, but for a full feature set,
  including stream routing and service mesh abilities with mutual TLS,
  you need Kong's [openresty-patches](https://github.com/kong/openresty-patches).
  The minimum required OpenSSL version is 1.1.1. If you are building by
  hand, make sure all dependencies, including LuaRocks modules, are
  compiled using the same OpenSSL version.
  If you are installing Kong from one of our distribution packages, you are not
  affected by this change.

##### Configuration

- The default value for `cassandra_lb_policy` changed from `RoundRobin`
  to `RequestRoundRobin`.
- The Nginx configuration file has changed, which means that you need to update
  it if you are using a custom template. The changes are detailed in a diff
  included below.

<details>
<summary><strong>Click here to see the Nginx configuration changes</strong></summary>
<p>

```diff
diff --git a/kong/templates/nginx_kong.lua b/kong/templates/nginx_kong.lua
index d4e416bc..8f268ffd 100644
--- a/kong/templates/nginx_kong.lua
+++ b/kong/templates/nginx_kong.lua
@@ -66,7 +66,9 @@ upstream kong_upstream {
     balancer_by_lua_block {
         Kong.balancer()
     }
+> if upstream_keepalive > 0 then
     keepalive ${{UPSTREAM_KEEPALIVE}};
+> end
 }

 server {
@@ -85,7 +87,7 @@ server {
 > if proxy_ssl_enabled then
     ssl_certificate ${{SSL_CERT}};
     ssl_certificate_key ${{SSL_CERT_KEY}};
-    ssl_protocols TLSv1.1 TLSv1.2;
+    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
     ssl_certificate_by_lua_block {
         Kong.ssl_certificate()
     }
@@ -200,7 +202,7 @@ server {
 > if admin_ssl_enabled then
     ssl_certificate ${{ADMIN_SSL_CERT}};
     ssl_certificate_key ${{ADMIN_SSL_CERT_KEY}};
-    ssl_protocols TLSv1.1 TLSv1.2;
+    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;

     ssl_session_cache shared:SSL:10m;
     ssl_session_timeout 10m;
```

</p>
</details>

- Kong generates a new template file for stream routing,
  `nginx-kong-stream.conf`, included in the `stream` block
  of its top-level Nginx configuration file. If you use
  a custom Nginx configuration and wish to use stream
  routing, you can generate this file using `kong prepare`.

##### Core

- The old DAO implementation (`kong.dao`) is no longer
  used by the Kong core,  which includes the old schema
  validation library. This has implications to plugin
  developers, listed below.
  - The last remaining entities that were converted to
    the new DAO implementation were Plugins, Upstreams
    and Targets. This has implications to the Admin API,
    listed below.

##### Plugins

Kong 0.15 includes version 1.0.0 of the Plugin Development Kit (PDK). No major
changes are made to the PDK compared to release 0.14, but some older non-PDK
functionality which was possibly used by custom plugins is now removed.

- Plugins now use the new schema format introduced by the
  new DAO implementation, for both plugin schemas
  (in `schema.lua`) and custom DAO entities (`daos.lua`).
  To ease the transition of plugins, the plugin loader
  in 0.15 includes a *best-effort* schema auto-translator
  for `schema.lua`, which should be sufficient for many
  plugins (in 1.0.0rc1, our bundled plugins used the
  auto-translator; they now use the new format).
  - If your plugin using the old format in `schema.lua`
    fails to load, check the error logs for messages
    produced by the auto-translator. If a field cannot
    be auto-translated, you can make a gradual conversion
    of the schema file by adding a `new_type` entry to
    the field table translation of the format. See,
    for example, the [key-auth schema in 1.0.0rc1](https://github.com/Kong/kong/blob/1.0.0rc1/kong/plugins/key-auth/schema.lua#L39-L54).
    The `new_type` annotation is ignored by Kong 0.x.
  - If your custom plugin uses custom DAO objects (i.e.
    if it includes a `daos.lua` file), it needs to be
    converted to the new format. Their code also needs
    to be adjusted accordingly, replacing uses of
    `singletons.dao` or `kong.dao` by `kong.db` (note
    that this module exposes a different API from the
    old DAO implementation).

##### Admin API

- All entity endpoints now use the new Admin API implementation.
  This means their requests and responses now use the same
  syntax, which was already in use in endpoints such as
  `/routes` and `/services`.
  - All endpoints now use the same syntax for
    referencing other entities as `/routes`
    (for example, `"service":{"id":"..."}` instead of
    `"service_id":"..."`), both in requests and responses.
    - This change affects `/plugins` as well as
      plugin-specific endpoints.
  - Array-typed values are not specified as a
    comma-separated list anymore. It must be specified as a
    JSON array or using the various formats supported by
    the url-formencoded array notation of the new Admin API
    implementation (`a[1]=x&a[2]=y`, `a[]=x&a[]=y`,
    `a=x&a=y`).
    - This change affects attributes of the `/upstreams` endpoint.
  - Error responses for the updated endpoints use
    the new standardized format.
  - As a result of being moved to the new Admin API implementation,
    all endpoints supporting `PUT` do so with proper semantics.
  - See the [Admin API
    reference](https://docs.konghq.com/0.15/admin-api)
    for more details.

#### 2. Deprecation Notices

Kong 0.15 retains the deprecation notices of previous releases; all modules
and concepts that have been marked as deprecated in previous releases are
retained in 0.15 but are removed in 1.0. See the Kong 1.0 changelog and
upgrade path for a detailed list.

#### 3. Suggested Upgrade Path

##### Preliminary Checks

If your cluster is running a version lower than 0.14, you need to
upgrade to 0.14.1 first instead. Upgrading from a pre-0.14 cluster
straight to Kong 0.15 is **not** supported.

If you use additional plugins other than the ones bundled with Kong,
make sure they are compatible with Kong 0.15 prior to upgrading.
See the section above on Plugins for information on plugin compatibility.

##### Migration Steps from 0.14

Kong 0.15 introduces a new, improved migrations framework.
It supports a no-downtime, Blue/Green migration model for upgrading
from 0.14.x. The full migration is now split into two steps,
which are performed via commands `kong migrations up` and
`kong migrations finish`.

For a no-downtime migration from a 0.14 cluster to a 0.15 cluster,
we recommend the following sequence of steps:

1. Download 0.15, and configure it to point to the same datastore
   as your 0.14 cluster. Run `kong migrations up`.
2. Both 0.14 and 0.15 nodes can now run simultaneously on the same
   datastore. Start provisioning 0.15 nodes, but do not use their
   Admin API yet. Prefer making Admin API requests to your 0.14 nodes
   instead.
3. Gradually divert traffic away from your 0.14 nodes, and into
   your 0.15 cluster. Monitor your traffic to make sure everything
   is going smoothly.
4. When your traffic is fully migrated to the 0.15 cluster,
   decommission your 0.14 nodes.
5. From your 0.15 cluster, run: `kong migrations finish`.
   From this point on, it will not be possible to start 0.14
   nodes pointing to the same datastore anymore. Only run
   this command when you are confident that your migration
   was successful. From now on, you can safely make Admin API
   requests to your 0.15 nodes.

##### Installing 0.15 on a Fresh Datastore

For installing on a fresh datastore, Kong 0.15 introduces the `kong migrations
bootstrap` command. The following commands can be run to prepare a new 0.15
cluster from a fresh datastore:

```
$ kong migrations bootstrap [-c config]
$ kong start [-c config]
```

## Upgrade to `0.14.x`

This version introduces **changes in Admin API endpoints**, **database
migrations**, **Nginx configuration changes**, and **removed configuration
properties**.

In this release, the **API entity is still supported**, along with its related
Admin API endpoints.

This section will highlight breaking changes that you need to be aware of
before upgrading and will describe the recommended upgrade path. We recommend
that you consult the full [0.14.0
Changelog](https://github.com/Kong/kong/blob/master/CHANGELOG.md) for a
complete list of changes and new features.

#### 1. Breaking Changes

##### Dependencies

- The required OpenResty version has been bumped to 1.13.6.2. If you
  are installing Kong from one of our distribution packages, you are not
  affected by this change.
- Support for PostreSQL 9.4 (deprecated in 0.12.0) is now dropped.
- Support for Cassandra 2.1 (deprecated in 0.12.0) is now dropped.

##### Configuration

- The `server_tokens` and `latency_tokens` configuration properties have been
  removed. Instead, a new `headers` configuration properties replaces them.
  See the default configuration file or the [configuration
  reference](https://docs.konghq.com/0.14.x/configuration/) for more details.
- The Nginx configuration file has changed, which means that you need to update
  it if you are using a custom template. The changes are detailed in a diff
  included below.

##### Plugins
- The Runscope plugin has been dropped, based on the EoL announcement made by Runscope about their Traffic Inspector product. [#3495](https://github.com/Kong/kong/pull/3495)

##### Admin API
- The SSL Certificates and SNI entities have moved to the new DAO implementation. As such, the /certificates and /snis endpoints have received notable usability improvements, but suffer from a few breaking changes. [#3386](https://github.com/Kong/kong/pull/3386)

- The Consumers entity has moved to the new DAO implementation. As such, the `/consumers` endpoint has received notable usability improvements, but suffers from a few breaking changes. [#3437](https://github.com/Kong/kong/pull/3437)

<details>
<summary><strong>Click here to see the Nginx configuration changes</strong></summary>
<p>

```diff
diff --git a/kong/templates/nginx_kong.lua b/kong/templates/nginx_kong.lua
index a66c230f..d4e416bc 100644
--- a/kong/templates/nginx_kong.lua
+++ b/kong/templates/nginx_kong.lua
@@ -29,8 +29,9 @@ lua_socket_pool_size ${{LUA_SOCKET_POOL_SIZE}};
 lua_max_running_timers 4096;
 lua_max_pending_timers 16384;
 lua_shared_dict kong                5m;
-lua_shared_dict kong_cache          ${{MEM_CACHE_SIZE}};
+lua_shared_dict kong_db_cache       ${{MEM_CACHE_SIZE}};
 lua_shared_dict kong_db_cache_miss 12m;
+lua_shared_dict kong_locks          8m;
 lua_shared_dict kong_process_events 5m;
 lua_shared_dict kong_cluster_events 5m;
 lua_shared_dict kong_healthchecks   5m;
@@ -44,13 +45,18 @@ lua_ssl_trusted_certificate '${{LUA_SSL_TRUSTED_CERTIFICATE}}';
 lua_ssl_verify_depth ${{LUA_SSL_VERIFY_DEPTH}};
 > end

+# injected nginx_http_* directives
+> for _, el in ipairs(nginx_http_directives)  do
+$(el.name) $(el.value);
+> end
+
 init_by_lua_block {
-    kong = require 'kong'
-    kong.init()
+    Kong = require 'kong'
+    Kong.init()
 }

 init_worker_by_lua_block {
-    kong.init_worker()
+    Kong.init_worker()
 }


@@ -58,7 +64,7 @@ init_worker_by_lua_block {
 upstream kong_upstream {
     server 0.0.0.1;
     balancer_by_lua_block {
-        kong.balancer()
+        Kong.balancer()
     }
     keepalive ${{UPSTREAM_KEEPALIVE}};
 }
@@ -81,7 +87,7 @@ server {
     ssl_certificate_key ${{SSL_CERT_KEY}};
     ssl_protocols TLSv1.1 TLSv1.2;
     ssl_certificate_by_lua_block {
-        kong.ssl_certificate()
+        Kong.ssl_certificate()
     }

     ssl_session_cache shared:SSL:10m;
@@ -101,7 +107,15 @@ server {
     set_real_ip_from   $(trusted_ips[i]);
 > end

+    # injected nginx_proxy_* directives
+> for _, el in ipairs(nginx_proxy_directives)  do
+    $(el.name) $(el.value);
+> end
+
     location / {
+        default_type                     '';
+
+        set $ctx_ref                     '';
         set $upstream_host               '';
         set $upstream_upgrade            '';
         set $upstream_connection         '';
@@ -113,11 +127,11 @@ server {
         set $upstream_x_forwarded_port   '';

         rewrite_by_lua_block {
-            kong.rewrite()
+            Kong.rewrite()
         }

         access_by_lua_block {
-            kong.access()
+            Kong.access()
         }

         proxy_http_version 1.1;
@@ -135,22 +149,36 @@ server {
         proxy_pass         $upstream_scheme://kong_upstream$upstream_uri;

         header_filter_by_lua_block {
-            kong.header_filter()
+            Kong.header_filter()
         }

         body_filter_by_lua_block {
-            kong.body_filter()
+            Kong.body_filter()
         }

         log_by_lua_block {
-            kong.log()
+            Kong.log()
         }
     }

     location = /kong_error_handler {
         internal;
+        uninitialized_variable_warn off;
+
         content_by_lua_block {
-            kong.handle_error()
+            Kong.handle_error()
+        }
+
+        header_filter_by_lua_block {
+            Kong.header_filter()
+        }
+
+        body_filter_by_lua_block {
+            Kong.body_filter()
+        }
+
+        log_by_lua_block {
+            Kong.log()
         }
     }
 }
@@ -180,10 +208,15 @@ server {
     ssl_ciphers ${{SSL_CIPHERS}};
 > end

+    # injected nginx_admin_* directives
+> for _, el in ipairs(nginx_admin_directives)  do
+    $(el.name) $(el.value);
+> end
+
     location / {
         default_type application/json;
         content_by_lua_block {
-            kong.serve_admin_api()
+            Kong.serve_admin_api()
         }
     }
```

</p>
</details>

##### Core

- If you are relying on passive health-checks to detect TCP timeouts, you
  should double-check your health-check configurations. Previously, timeouts
  were erroneously contributing to the `tcp_failures` counter. They are now
  properly contributing to the `timeout` counter. In order to short-circuit
  traffic based on timeouts, you must ensure that your `timeout` settings
  are properly configured. See the [Health Checks
  reference](https://docs.konghq.com/0.14.x/health-checks-circuit-breakers/)
  for more details.

##### Plugins

- Custom plugins can now see their `header_filter`, `body_filter`, and `log`
  phases executed without the `rewrite` or `access` phases running first. This
  can happen when Nginx itself produces an error while parsing the client's
  request. Similarly, `ngx.var` values (e.g. `ngx.var.request_uri`) may be
  `nil`. Plugins should be hardened to handle such cases and avoid using
  uninitialized variables, which could throw Lua errors.
- The Runscope plugin has been dropped, based on the EoL announcement made by
  Runscope about their Traffic Inspector product.

##### Admin API

- As a result of being moved to the new Admin API implementation (and
  supporting `PUT` and named endpoints), the `/snis` endpoint
  `ssl_certificate_id` attribute has been renamed to `certificate_id`.
  See the [Admin API
  reference](https://docs.konghq.com/0.14.x/admin-api/#add-sni) for
  more details.
- On the `/certificates` endpoint, the `snis` attribute is not specified as a
  comma-separated list anymore. It must be specified as a JSON array or using
  the url-formencoded array notation of other recent Admin API endpoints. See
  the [Admin API
  reference](https://docs.konghq.com/0.14.x/admin-api/#add-certificate) for
  more details.
- Filtering by username in the `/consumers` endpoint is not supported with
  `/consumers?username=...`. Instead, use `/consumers/{username}` to retrieve a
  Consumer by its username. Filtering with `/consumers?custom_id=...` is still
  supported.

#### 2. Deprecation Notices

- The `custom_plugins` configuration property is now deprecated in favor of
  `plugins`. See the default configuration file or the [configuration
  reference](https://docs.konghq.com/0.14.x/configuration/) for more details.

#### 3. Suggested Upgrade Path

You can now start migrating your cluster from `0.13.x` to `0.14`. If you are
doing this upgrade "in-place", against the datastore of a running 0.13 cluster,
then for a short period of time, your database schema won't be fully compatible
with your 0.13 nodes anymore. This is why we suggest either performing this
upgrade when your 0.13 cluster is warm and most entities are cached, or against
a new database, if you can migrate your data. If you wish to temporarily make
your APIs unavailable, you can leverage the
[request-termination](https://getkong.org/plugins/request-termination/) plugin.

The path to upgrade a 0.13 datastore is identical to the one of previous major
releases:

1. If you are planning on upgrading Kong while 0.13 nodes are running against
   the same datastore, make sure those nodes are warm enough (they should have
   most of your entities cached already), or temporarily disable your APIs.
2. Provision a 0.14 node and configure it as you wish (environment variables/
   configuration file). Make sure to point this new 0.14 node to your current
   datastore.
3. **Without starting the 0.14 node**, run the 0.14 migrations against your
   current datastore:

```
$ kong migrations up [-c kong.conf]
```

As usual, this step should be executed from a **single node**.

4. You can now provision a fresh 0.14 cluster pointing to your migrated
   datastore and start your 0.14 nodes.
5. Gradually switch your traffic from the 0.13 cluster to the new 0.14 cluster.
   Remember, once your database is migrated, your 0.13 nodes will rely on
   their cache and not on the underlying database. Your traffic should switch
   to the new cluster as quickly as possible.
6. Once your traffic is fully migrated to the 0.14 cluster, decommission
   your 0.13 cluster.

You have now successfully upgraded your cluster to run 0.14 nodes exclusively.

## Upgrade to `0.13.x`

This version comes with **new model entities**, **database migrations**, and
**nginx configuration changes**.

This section will only highlight the breaking changes that you need to be
aware of, and describe a recommended upgrade path. We recommend that you
consult the full [0.13.0
Changelog](https://github.com/Kong/kong/blob/master/CHANGELOG.md) for a
complete list of changes and new features.

See below the breaking changes section for a detailed list of steps recommended
to **run migrations** and upgrade from a previous version of Kong.

#### 1. Breaking Changes

- **Note to Docker users**: The `latest` tag on Docker Hub now points to the
  **alpine** image instead of CentOS. This also applies to the `0.13.0` tag.

##### Dependencies

- Support for Cassandra 2.1 was deprecated in 0.12.0 and has been dropped
  starting with 0.13.0.
- Various dependencies have been bumped. Once again, consult the Changelog for
  a detailed list.

##### Configuration

- The `proxy_listen` and `admin_listen` configuration values have a new syntax.
  See the configuration file or the [0.13.x
  documentation](https://getkong.org/docs/0.13.x/configuration/) for insights
  on the new syntax.
- The nginx configuration file has changed, which means that you need to update
  it if you are using a custom template. The changes are detailed in a diff
  included below.

<details>
<summary><strong>Click here to see the nginx configuration changes</strong></summary>
<p>

```diff
diff --git a/kong/templates/nginx_kong.lua b/kong/templates/nginx_kong.lua
index 5639f319..62f5f1ae 100644
--- a/kong/templates/nginx_kong.lua
+++ b/kong/templates/nginx_kong.lua
@@ -51,6 +51,8 @@ init_worker_by_lua_block {
     kong.init_worker()
 }

+
+> if #proxy_listeners > 0 then
 upstream kong_upstream {
     server 0.0.0.1;
     balancer_by_lua_block {
@@ -61,7 +63,9 @@ upstream kong_upstream {

 server {
     server_name kong;
-    listen ${{PROXY_LISTEN}}${{PROXY_PROTOCOL}};
+> for i = 1, #proxy_listeners do
+    listen $(proxy_listeners[i].listener);
+> end
     error_page 400 404 408 411 412 413 414 417 /kong_error_handler;
     error_page 500 502 503 504 /kong_error_handler;

@@ -70,8 +74,7 @@ server {

     client_body_buffer_size ${{CLIENT_BODY_BUFFER_SIZE}};

-> if ssl then
-    listen ${{PROXY_LISTEN_SSL}} ssl${{HTTP2}}${{PROXY_PROTOCOL}};
+> if proxy_ssl_enabled then
     ssl_certificate ${{SSL_CERT}};
     ssl_certificate_key ${{SSL_CERT_KEY}};
     ssl_protocols TLSv1.1 TLSv1.2;
@@ -149,10 +152,14 @@ server {
         }
     }
 }
+> end

+> if #admin_listeners > 0 then
 server {
     server_name kong_admin;
-    listen ${{ADMIN_LISTEN}};
+> for i = 1, #admin_listeners do
+    listen $(admin_listeners[i].listener);
+> end

     access_log ${{ADMIN_ACCESS_LOG}};
     error_log ${{ADMIN_ERROR_LOG}} ${{LOG_LEVEL}};
@@ -160,8 +167,7 @@ server {
     client_max_body_size 10m;
     client_body_buffer_size 10m;

-> if admin_ssl then
-    listen ${{ADMIN_LISTEN_SSL}} ssl${{ADMIN_HTTP2}};
+> if admin_ssl_enabled then
     ssl_certificate ${{ADMIN_SSL_CERT}};
     ssl_certificate_key ${{ADMIN_SSL_CERT_KEY}};
     ssl_protocols TLSv1.1 TLSv1.2;
@@ -189,4 +195,5 @@ server {
         return 200 'User-agent: *\nDisallow: /';
     }
 }
+> end
```

</p>
</details>

##### Plugins

- The galileo plugin is considered deprecated and not enabled by default
  anymore. It is still shipped with Kong 0.13.0, but you must enable it by
  specifying it in the `custom_plugins` configuration property, like so:
  `custom_plugins = galileo` (or via the `KONG_CUSTOM_PLUGINS` environment
  variable).
- The migrations will remove and re-create the rate-limiting and
  response-ratelimiting tables storing counters. This means that your counters
  will reset.

#### 2. Deprecation Notices

Starting with 0.13.0, the "API" entity is considered **deprecated**. While
still supported, we will eventually remove the entity and its related endpoints
from the Admin API. Services and Routes are the new first-class citizen
entities that new users (or users upgrading their clusters) should configure.

You can read more about Services and Routes in the [Proxy
Guide](https://getkong.org/docs/0.13.x/proxy/) and the [Admin API
Reference](https://getkong.org/docs/0.13.x/admin-api/).

#### 3. Suggested Upgrade Path

You can now start migrating your cluster from `0.12.x` to `0.13`. If you are
doing this upgrade "in-place", against the datastore of a running 0.12 cluster,
then for a short period of time, your database schema won't be fully compatible
with your 0.12 nodes anymore. This is why we suggest either performing this
upgrade when your 0.12 cluster is warm and most entities are cached, or against
a new database if you can migrate your data. If you wish to temporarily make
your APIs unavailable, you can leverage the
[request-termination](https://getkong.org/plugins/request-termination/) plugin.

The path to upgrade a 0.12 datastore is identical to the one of previous major
releases:

1. If you are planning on upgrading Kong while 0.12 nodes are running against
   the same datastore, make sure those nodes are warm enough (they should have
   most of your entities cached already) or temporarily disable your APIs.
2. Provision a 0.13 node and configure it as you wish (environment variables/
   configuration file). Make sure to point this new 0.13 node to your current
   datastore.
3. **Without starting the 0.13 node**, run the 0.13 migrations against your
   current datastore:

```
$ kong migrations up [-c kong.conf]
```

As usual, this step should be executed from a **single node**.

4. You can now provision a fresh 0.13 cluster pointing to your migrated
   datastore and start your 0.13 nodes.
5. Gradually switch your traffic from the 0.12 cluster to the new 0.13 cluster.
   Remember, once your database is migrated, your 0.12 nodes will rely on
   their cache and not on the underlying database. Your traffic should switch
   to the new cluster as quickly as possible.
6. Once your traffic is fully migrated to the 0.13 cluster, decommission
   your 0.12 cluster.

You have now successfully upgraded your cluster to run 0.13 nodes exclusively.

## Upgrade to `0.12.x`

As it is the case most of the time, this new major version of Kong comes with
a few **database migrations**, some breaking changes, databases deprecation
notices, and minor updates to the NGINX configuration template.

This document will only highlight the breaking changes that you need to be
aware of, and describe a recommended upgrade path. We recommend that you
consult the full [0.12.0
Changelog](https://github.com/Kong/kong/blob/master/CHANGELOG.md) for a
complete list of changes and new features.

See below the breaking changes section for a detailed list of steps recommended
to **run migrations** and upgrade from a previous version of Kong.

#### Deprecation notices

Starting with 0.12.0, we are announcing the deprecation of older versions
of our supported databases:

- Support for PostgreSQL 9.4 is deprecated. Users are advised to upgrade to
  9.5+
- Support for Cassandra 2.1 and below is deprecated. Users are advised to
  upgrade to 2.2+

Note that the above-deprecated versions are still supported in this release,
but will be dropped in subsequent ones.

#### Breaking changes

##### Configuration

- Several updates were made to the NGINX configuration template. If you are
  using a custom template, you **must** apply those modifications. See below
  for a list of changes to apply.

##### Core

- The required OpenResty version has been bumped to 1.11.2.5. If you
  are installing Kong from one of our distribution packages, you are not
  affected by this change.
- As Kong now executes subsequent plugins when a request is being
  short-circuited (e.g. HTTP 401 responses from auth plugins), plugins that
  run in the header or body filter phases will be run upon such responses
  from the access phase. It is possible that some of these plugins (e.g. your
  custom plugins) now run in scenarios where they were not previously expected
  to run.

##### Admin API

- By default, the Admin API now only listens on the local interface.
  We consider this change to be an improvement in the default security policy
  of Kong. If you are already using Kong, and your Admin API still binds to all
  interfaces, consider updating it as well. You can do so by updating the
  `admin_listen` configuration value, like so: `admin_listen = 127.0.0.1:8001`.

  :red_circle: **Note to Docker users**: Beware of this change as you may have
  to ensure that your Admin API is reachable via the host's interface.
  You can use the `-e KONG_ADMIN_LISTEN` argument when provisioning your
  container(s) to update this value; for example,
  `-e KONG_ADMIN_LISTEN=0.0.0.0:8001`.

- The `/upstreams/:upstream_name_or_id/targets/` has been updated to not show
  the full list of Targets anymore, but only the ones that are currently
  active in the load balancer. To retrieve the full history of Targets, you can
  now query `/upstreams/:upstream_name_or_id/targets/all`. The
  `/upstreams/:upstream_name_or_id/targets/active` endpoint has been removed.
- The `orderlist` property of Upstreams has been removed.

##### CLI

- The `$ kong compile` command which was deprecated in 0.11.0 has been removed.

##### Plugins

- In logging plugins, the `request.request_uri` field has been renamed to
  `request.url`.

---

If you use a custom NGINX configuration template from Kong 0.11, before
attempting to run any 0.12 node, make sure to apply the following change to
your template:

```diff
diff --git a/kong/templates/nginx_kong.lua b/kong/templates/nginx_kong.lua
index 5ab65ca3..8a6abd64 100644
--- a/kong/templates/nginx_kong.lua
+++ b/kong/templates/nginx_kong.lua
@@ -32,6 +32,7 @@ lua_shared_dict kong                5m;
 lua_shared_dict kong_cache          ${{MEM_CACHE_SIZE}};
 lua_shared_dict kong_process_events 5m;
 lua_shared_dict kong_cluster_events 5m;
+lua_shared_dict kong_healthchecks   5m;
 > if database == "cassandra" then
 lua_shared_dict kong_cassandra      5m;
 > end
```

---

You can now start migrating your cluster from `0.11.x` to `0.12`. If you are
doing this upgrade "in-place", against the datastore of a running 0.11 cluster,
then for a short period of time, your database schema won't be fully compatible
with your 0.11 nodes anymore. This is why we suggest either performing this
upgrade when your 0.11 cluster is warm and most entities are cached, or against
a new database, if you can migrate your data. If you wish to temporarily make
your APIs unavailable, you can leverage the
[request-termination](https://getkong.org/plugins/request-termination/) plugin.

The path to upgrade a 0.11 datastore is identical to the one of previous major
releases:

1. If you are planning on upgrading Kong while 0.11 nodes are running against
   the same datastore, make sure those nodes are warm enough (they should have
   most of your entities cached already), or temporarily disable your APIs.
2. Provision a 0.12 node and configure it as you wish (environment variables/
   configuration file). Make sure to point this new 0.12 node to your current
   datastore.
3. **Without starting the 0.12 node**, run the 0.12 migrations against your
   current datastore:

```
$ kong migrations up [-c kong.conf]
```

As usual, this step should be executed from a **single node**.

4. You can now provision a fresh 0.12 cluster pointing to your migrated
   datastore and start your 0.12 nodes.
5. Gradually switch your traffic from the 0.11 cluster to the new 0.12 cluster.
   Remember, once your database is migrated, your 0.11 nodes will rely on
   their cache and not on the underlying database. Your traffic should switch
   to the new cluster as quickly as possible.
6. Once your traffic is fully migrated to the 0.12 cluster, decommission
   your 0.11 cluster.

You have now successfully upgraded your cluster to run 0.12 nodes exclusively.

## Upgrade to `0.11.x`

Along with the usual database migrations shipped with our major releases, this
particular release introduces quite a few changes in behavior and, most
notably, the enforced manual migrations process and the removal of the Serf
dependency for cache invalidation between Kong nodes of the same cluster.

This document will only highlight the breaking changes that you need to be
aware of, and describe a recommended upgrade path. We recommend that you
consult the full [0.11.0
Changelog](https://github.com/Kong/kong/blob/master/CHANGELOG.md) for a
complete list of changes and new features.

#### Breaking changes

##### Configuration

- Several updates were made to the Nginx configuration template. If you are
  using a custom template, you **must** apply those modifications. See below
  for a list of changes to apply.

##### Migrations & Deployment

- Migrations are **not** executed automatically by `kong start` anymore.
  Migrations are now a **manual** process, which must be executed via the `kong
  migrations` command. In practice, this means that you have to run `kong
  migrations up [-c kong.conf]` in one of your nodes **before** starting your
  Kong nodes. This command should be run from a **single** node/container to
  avoid several nodes running migrations concurrently and potentially
  corrupting your database. Once the migrations are up-to-date, it is
  considered safe to start multiple Kong nodes concurrently.
- Serf is **not** a dependency anymore. Kong nodes now handle cache
  invalidation events via a built-in database polling mechanism. See the new
  "Datastore Cache" section of the configuration file which contains 3 new
  documented properties: `db_update_frequency`, `db_update_propagation`, and
  `db_cache_ttl`.  If you are using Cassandra, you **should** pay a particular
  attention to the `db_update_propagation` setting, as you **should not** use
  the default value of `0`.

**Note for Docker users:** Because of the aforementioned breaking change, if
you are running Kong with Docker, you will now need to run the migrations from
a single, ephemeral container. You can follow the [Docker installation
instructions](https://getkong.org/install/docker/) (see "2. Prepare your
database") for more details about this process.

##### Core

- Kong now requires OpenResty `1.11.2.4`. OpenResty's LuaJIT can now be built
  with Lua 5.2 compatibility, and the `--without-luajit-lua52` flag can be
  omitted.
- While Kong now correctly proxies downstream `X-Forwarded-*` headers, the
  introduction of the new `trusted_ips` property also means that Kong will
  only do so when the request comes from a trusted client IP. This is also
  the condition under which the `X-Real-IP` header will be trusted by Kong
  or not.
  In order to enforce security best practices, we took the stance of **not**
  trusting any client IP by default. If you wish to rely on such headers, you
  will need to configure `trusted_ips` (see the Kong configuration file) to
  your needs.
- The API Object property `http_if_terminated` is now set to `false` by
  default. For Kong to evaluate the client `X-Forwarded-Proto` header, you must
  now configure Kong to trust the client IP (see above change), **and** you
  must explicitly set this value to `true`. This affects you if you are doing
  SSL termination somewhere before your requests hit Kong, and if you have
  configured `https_only` on the API, or if you use a plugin that requires
  HTTPS traffic (e.g. OAuth2).
- The internal DNS resolver now honours the `search` and `ndots` configuration
  options of your `resolv.conf` file. Make sure that DNS resolution is still
  consistent in your environment, and consider eventually not using FQDNs
  anymore.

##### Admin API

- Due to the removal of Serf, Kong is now entirely stateless. As such, the
  `/cluster` endpoint has for now disappeared. This endpoint, in previous
  versions of Kong, retrieved the state of the Serf agent running on other
  nodes to ensure they were part of the same cluster. Starting from 0.11, all
  Kong nodes connected to the same datastore are guaranteed to be part of the
  same cluster without requiring additional channels of communication.
- The Admin API `/status` endpoint does not return a count of the database
  entities anymore. Instead, it now returns a `database.reachable` boolean
  value, which reflects the state of the connection between Kong and the
  underlying database. Please note that this flag **does not** reflect the
  health of the database itself.

##### Plugins development

- The upstream URI is now determined via the Nginx `$upstream_uri` variable.
  Custom plugins using the `ngx.req.set_uri()` API will not be taken into
  consideration anymore. One must now set the `ngx.var.upstream_uri` variable
  from the Lua land.
- The `hooks.lua` module for custom plugins is dropped, along with the
  `database_cache.lua` module. Database entities caching and eviction has been
  greatly improved to simplify and automate most caching use-cases. See the
  [plugins development
  guide](https://getkong.org/docs/0.11.x/plugin-development/entities-cache/)
  for more details about the new underlying mechanism, or see the below
  section of this document on how to update your plugin's cache invalidation
  mechanism for 0.11.0.
- To ensure that the order of execution of plugins is still the same for
  vanilla Kong installations, we had to update the `PRIORITY` field of some of
  our bundled plugins. If your custom plugin must run after or before a
  specific bundled plugin, you might have to update your plugin's `PRIORITY`
  field as well. The complete list of plugins and their priorities is available
  on the [plugins development
  guide](https://getkong.org/docs/0.11.x/plugin-development/custom-logic/).

#### Deprecations

##### CLI

- The `kong compile` command has been deprecated. Instead, prefer using
  the new `kong prepare` command.

---

If you use a custom Nginx configuration template from Kong 0.10, before
attempting to run any 0.11 node, make sure to apply the following changes to
your template:

```diff
diff --git a/kong/templates/nginx_kong.lua b/kong/templates/nginx_kong.lua
index 3c038595..faa97ffe 100644
--- a/kong/templates/nginx_kong.lua
+++ b/kong/templates/nginx_kong.lua
@@ -19,25 +19,23 @@ error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};
 >-- reset_timedout_connection on; # disabled until benchmarked
 > end

-client_max_body_size 0;
+client_max_body_size ${{CLIENT_MAX_BODY_SIZE}};
 proxy_ssl_server_name on;
 underscores_in_headers on;

-real_ip_header X-Forwarded-For;
-set_real_ip_from 0.0.0.0/0;
-real_ip_recursive on;
-
 lua_package_path '${{LUA_PACKAGE_PATH}};;';
 lua_package_cpath '${{LUA_PACKAGE_CPATH}};;';
 lua_code_cache ${{LUA_CODE_CACHE}};
 lua_socket_pool_size ${{LUA_SOCKET_POOL_SIZE}};
 lua_max_running_timers 4096;
 lua_max_pending_timers 16384;
-lua_shared_dict kong 4m;
-lua_shared_dict cache ${{MEM_CACHE_SIZE}};
-lua_shared_dict cache_locks 100k;
-lua_shared_dict process_events 1m;
-lua_shared_dict cassandra 5m;
+lua_shared_dict kong                5m;
+lua_shared_dict kong_cache          ${{MEM_CACHE_SIZE}};
+lua_shared_dict kong_process_events 5m;
+lua_shared_dict kong_cluster_events 5m;
+> if database == "cassandra" then
+lua_shared_dict kong_cassandra      5m;
+> end
 lua_socket_log_errors off;
 > if lua_ssl_trusted_certificate then
 lua_ssl_trusted_certificate '${{LUA_SSL_TRUSTED_CERTIFICATE}}';
@@ -45,8 +43,6 @@ lua_ssl_verify_depth ${{LUA_SSL_VERIFY_DEPTH}};
 > end

 init_by_lua_block {
-    require 'luarocks.loader'
-    require 'resty.core'
     kong = require 'kong'
     kong.init()
 }
@@ -65,28 +61,19 @@ upstream kong_upstream {
     keepalive ${{UPSTREAM_KEEPALIVE}};
 }

-map $http_upgrade $upstream_connection {
-    default keep-alive;
-    websocket upgrade;
-}
-
-map $http_upgrade $upstream_upgrade {
-    default '';
-    websocket websocket;
-}
-
 server {
     server_name kong;
-    listen ${{PROXY_LISTEN}};
-    error_page 404 408 411 412 413 414 417 /kong_error_handler;
+    listen ${{PROXY_LISTEN}}${{PROXY_PROTOCOL}};
+    error_page 400 404 408 411 412 413 414 417 /kong_error_handler;
     error_page 500 502 503 504 /kong_error_handler;

     access_log ${{PROXY_ACCESS_LOG}};
     error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

+    client_body_buffer_size ${{CLIENT_BODY_BUFFER_SIZE}};

 > if ssl then
-    listen ${{PROXY_LISTEN_SSL}} ssl;
+    listen ${{PROXY_LISTEN_SSL}} ssl${{HTTP2}}${{PROXY_PROTOCOL}};
     ssl_certificate ${{SSL_CERT}};
     ssl_certificate_key ${{SSL_CERT_KEY}};
     ssl_protocols TLSv1.1 TLSv1.2;
@@ -105,9 +92,22 @@ server {
     proxy_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
 > end

+    real_ip_header     ${{REAL_IP_HEADER}};
+    real_ip_recursive  ${{REAL_IP_RECURSIVE}};
+> for i = 1, #trusted_ips do
+    set_real_ip_from   $(trusted_ips[i]);
+> end
+
     location / {
-        set $upstream_host nil;
-        set $upstream_scheme nil;
+        set $upstream_host               '';
+        set $upstream_upgrade            '';
+        set $upstream_connection         '';
+        set $upstream_scheme             '';
+        set $upstream_uri                '';
+        set $upstream_x_forwarded_for    '';
+        set $upstream_x_forwarded_proto  '';
+        set $upstream_x_forwarded_host   '';
+        set $upstream_x_forwarded_port   '';

         rewrite_by_lua_block {
             kong.rewrite()
@@ -118,17 +118,18 @@ server {
         }

         proxy_http_version 1.1;
-        proxy_set_header X-Real-IP $remote_addr;
-        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
-        proxy_set_header X-Forwarded-Proto $scheme;
-        proxy_set_header Host $upstream_host;
-        proxy_set_header Upgrade $upstream_upgrade;
-        proxy_set_header Connection $upstream_connection;
-        proxy_pass_header Server;
-
-        proxy_ssl_name $upstream_host;
-
-        proxy_pass $upstream_scheme://kong_upstream;
+        proxy_set_header   Host              $upstream_host;
+        proxy_set_header   Upgrade           $upstream_upgrade;
+        proxy_set_header   Connection        $upstream_connection;
+        proxy_set_header   X-Forwarded-For   $upstream_x_forwarded_for;
+        proxy_set_header   X-Forwarded-Proto $upstream_x_forwarded_proto;
+        proxy_set_header   X-Forwarded-Host  $upstream_x_forwarded_host;
+        proxy_set_header   X-Forwarded-Port  $upstream_x_forwarded_port;
+        proxy_set_header   X-Real-IP         $remote_addr;
+        proxy_pass_header  Server;
+        proxy_pass_header  Date;
+        proxy_ssl_name     $upstream_host;
+        proxy_pass         $upstream_scheme://kong_upstream$upstream_uri;

         header_filter_by_lua_block {
             kong.header_filter()
@@ -146,7 +147,7 @@ server {
     location = /kong_error_handler {
         internal;
         content_by_lua_block {
-            require('kong.core.error_handlers')(ngx)
+            kong.handle_error()
         }
     }
 }
@@ -162,7 +163,7 @@ server {
     client_body_buffer_size 10m;

 > if admin_ssl then
-    listen ${{ADMIN_LISTEN_SSL}} ssl;
+    listen ${{ADMIN_LISTEN_SSL}} ssl${{ADMIN_HTTP2}};
     ssl_certificate ${{ADMIN_SSL_CERT}};
     ssl_certificate_key ${{ADMIN_SSL_CERT_KEY}};
     ssl_protocols TLSv1.1 TLSv1.2;
@@ -176,15 +177,7 @@ server {
     location / {
         default_type application/json;
         content_by_lua_block {
-            ngx.header['Access-Control-Allow-Origin'] = '*'
-
-            if ngx.req.get_method() == 'OPTIONS' then
-                ngx.header['Access-Control-Allow-Methods'] = 'GET,HEAD,PUT,PATCH,POST,DELETE'
-                ngx.header['Access-Control-Allow-Headers'] = 'Content-Type'
-                ngx.exit(204)
-            end
-
-            require('lapis').serve('kong.api')
+            kong.serve_admin_api()
         }
     }
```

Once those changes have been applied, you will be able to benefit from the new
configuration properties and bug fixes that 0.11 introduces.

---

If you are maintaining your own plugin, and if you are using the 0.10.x
`database_cache.lua` module to cache your datastore entities, you probably
included a `hooks.lua` module in your plugin as well.

In 0.11, most of the clutter surrounding cache invalidation is now gone, and
handled automatically by Kong for most use-cases.

- The `hooks.lua` module is now ignored by Kong. You can safely remove it from
  your plugins.
- The `database_cache.lua` module is replaced with `singletons.cache`. You
  should not require `database_cache` anymore in your plugin's code.

To update your plugin's caching mechanism to 0.11, you must implement automatic
or manual invalidation.

##### Automatic cache invalidation

Let's assume your plugin had the following code that we wish to update for
0.11 compatibility:

```lua
local credential, err = cache.get_or_set(cache.keyauth_credential_key(key),
                                         nil, load_credential, key)
if err then
  return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
end
```

Along with the following `hooks.lua` file:

```lua
local events = require "kong.core.events"
local cache = require "kong.tools.database_cache"

local function invalidate(message_t)
  if message_t.collection == "keyauth_credentials" then
    cache.delete(cache.keyauth_credential_key(message_t.old_entity     and
                                              message_t.old_entity.key or
                                              message_t.entity.key))
  end
end

return {
  [events.TYPES.ENTITY_UPDATED] = function(message_t)
    invalidate(message_t)
  end,
  [events.TYPES.ENTITY_DELETED] = function(message_t)
    invalidate(message_t)
  end
}
```

By adding the following `cache_key` property to your custom entity's schema:

```lua
local SCHEMA = {
  primary_key = { "id" },
  table = "keyauth_credentials",
  cache_key = { "key" }, -- cache key for this entity
  fields = {
    id = { type = "id" },
    consumer_id = { type = "id", required = true, foreign = "consumers:id"},
    key = { type = "string", required = false, unique = true }
  }
}

return { keyauth_credentials = SCHEMA }
```

You can now generate a unique cache key for that entity and cache it like so
in your business logic and hot code paths:

```lua
local singletons = require "kong.singletons"

local apikey = request.get_uri_args().apikey
local cache_key = singletons.dao.keyauth_credentials:cache_key(apikey)

local credential, err = singletons.cache:get(cache_key, nil, load_entity_key,
                                             apikey)
if err then
  return response.HTTP_INTERNAL_SERVER_ERROR(err)
end

-- do something with the retrieved credential
```

Now, cache invalidation will be an automatic process: every CRUD operation that
affects this API key will make Kong auto-generate the affected `cache_key`,
and send broadcast it to all of the other nodes on the cluster so they can
evict that particular value from their cache, and fetch the fresh value from
the datastore on the next request.

When a parent entity is receiving a CRUD operation (e.g. the Consumer owning
this API key, as per our schema's `consumer_id` attribute), Kong performs the
cache invalidation mechanism for both the parent and the child entity.

Thanks to this new property, the `hooks.lua` module is not required anymore and
your plugins can perform datastore caching much more easily.

##### Manual cache invalidation

In some cases, the `cache_key` property of an entity's schema is not flexible
enough, and one must manually invalidate its cache. Reasons for this could be
that the plugin is not defining a relationship with another entity via the
traditional `foreign = "parent_entity:parent_attribute"` syntax, or because
it is not using the `cache_key` method from its DAO, or even because it is
somehow abusing the caching mechanism.

In those cases, you can manually set up your own subscriber to the same
invalidation channels Kong is listening to, and perform your own, custom
invalidation work. This process is similar to the old `hooks.lua` module.

To listen on invalidation channels inside of Kong, implement the following in
your plugin's `init_worker` handler:

```lua
local singletons = require "kong.singletons"

function MyCustomHandler:init_worker()
  local worker_events = singletons.worker_events

  -- listen to all CRUD operations made on Consumers
  worker_events.register(function(data)

  end, "crud", "consumers")

  -- or, listen to a specific CRUD operation only
  worker_events.register(function(data)
    print(data.operation)  -- "update"
    print(data.old_entity) -- old entity table (only for "update")
    print(data.entity)     -- new entity table
    print(data.schema)     -- entity's schema
  end, "crud", "consumers:update")
end
```

Once the above listeners are in place for the desired entities, you can perform
manual invalidations of any entity that your plugin has cached as you wish so.
For instance:

```lua
singletons.worker_events.register(function(data)
  if data.operation == "delete" then
    local cache_key = data.entity.id
    singletons.cache:invalidate("prefix:" .. cache_key)
  end
end, "crud", "consumers")
```

---

You can now start migrating your cluster from `0.10.x` to `0.11`. If you are
doing this upgrade "in-place", against the datastore of a running 0.10 cluster,
then for a short period of time, your database schema won't be fully compatible
with your 0.10 nodes anymore. This is why we suggest either performing this
upgrade when your 0.10 cluster is warm and most entities are cached, or against
a new database, if you can migrate your data. If you wish to temporarily make
your APIs unavailable, you can leverage the new
[request-termination](https://getkong.org/plugins/request-termination/) plugin.

The path to upgrade a 0.10 datastore is identical to the one of previous major
releases:

1. If you are planning on upgrading Kong while 0.10 nodes are running against
   the same datastore, make sure those nodes are warm enough (they should have
   most of your entities cached already), or temporarily disable your APIs.
2. Provision a 0.11 node and configure it as you wish (environment variables/
   configuration file). Make sure to point this new 0.11 node to your current
   datastore.
3. **Without starting the 0.11 node**, run the 0.11 migrations against your
   current datastore:

```
$ kong migrations up [-c kong.conf]
```

As usual, this step should be executed from a **single node**.

4. You can now provision a fresh 0.11 cluster pointing to your migrated
   datastore and start your 0.11 nodes.
5. Gradually switch your traffic from the 0.10 cluster to the new 0.11 cluster.
   Remember, once your database is migrated, your 0.10 nodes will rely on
   their cache and not on the underlying database. Your traffic should switch
   to the new cluster as quickly as possible.
6. Once your traffic is fully migrated to the 0.11 cluster, decommission
   your 0.10 cluster.

Once all of your 0.10 nodes are fully decommissioned, you can consider removing
the Serf executable from your environment as well, since Kong 0.11 does not
depend on it anymore.

## Upgrade to `0.10.x`

Due to the breaking changes introduced in this version, we recommend that you
carefully test your cluster deployment.

Kong 0.10 introduced the following breaking changes:

- API Objects (as configured via the Admin API) do **not** support the
  `request_host` and `request_uri` fields anymore. The 0.10 migrations should
  upgrade your current API Objects, but make sure to read the new [0.10 Proxy
  Guide](https://getkong.org/docs/0.10.x/proxy) to learn the new routing
  capabilities of Kong. This means that Kong can now route incoming requests
  according to a combination of Host headers, URIs, and HTTP
  methods.
- The `upstream_url` field of API Objects does not accept trailing slashes anymore.
- Dynamic SSL certificates serving is now handled by the core and **not**
  through the `ssl` plugin anymore. This version introduced the `/certificates`
  and `/snis` endpoints. See the new [0.10 Proxy
  Guide](https://getkong.org/docs/0.10.x/proxy) to learn more about how to
  configure your SSL certificates on your APIs. The `ssl` plugin has been
  removed.
- The preferred version of OpenResty is now `1.11.2.2`. However, this version
  requires that you compiled OpenResty with the `--without-luajit-lua52` flag.
  Make sure to do so if you install OpenResty and Kong from source.
- Dnsmasq is not a dependency anymore (However, be careful before removing it
  if you configured it to be your DNS name server via Kong's [`resolver`
  property](https://getkong.org/docs/0.9.x/configuration/#dns-resolver-section))
- The `cassandra_contact_points` property does not allow specifying a port
  anymore. All Cassandra nodes must listen on the same port, which can be
  tweaked via the `cassandra_port` property.
- If you are upgrading to `0.10.1` or `0.10.2` and using the CORS plugin, pay
  extra attention to a regression that was introduced in `0.10.1`:
  Previously, the plugin would send the `*` wildcard when `config.origin` was
  not specified. With this change, the plugin **does not** send the `*`
  wildcard by default anymore. You will need to specify it manually when
  configuring the plugin, with `config.origins=*`. This behavior is to be fixed
  in a future release.

We recommend that you consult the full [0.10.0
Changelog](https://github.com/Kong/kong/blob/master/CHANGELOG.md) for a full
list of changes and new features, including load balancing capabilities,
support for Cassandra 3.x, SRV records resolution, and much more.

Here is how to ensure a smooth upgrade from a Kong `0.9.x` cluster to `0.10`:

1. Make sure your 0.9 cluster is warm because your
   datastore will be incompatible with your 0.9 Kong nodes once migrated.
   Most of your entities should be cached
   by the running Kong nodes already (APIs, Consumers, Plugins).
2. Provision a 0.10 node and configure it as you wish (environment variables/
   configuration file). Make sure to point this new 0.10 node to your current
   datastore.
3. **Without starting the 0.10 node**, run the 0.10 migrations against your
   current datastore:

```
$ kong migrations up <-c kong.conf>
```

As usual, this step should be executed from a single node.

4. You can now provision a fresh 0.10 cluster pointing to your migrated
   datastore and start your 0.10 nodes.
5. Gradually switch your traffic from the 0.9 cluster to the new 0.10 cluster.
   Remember, once your database is migrated, your 0.9 nodes will rely on
   their cache and not on the underlying database. Your traffic should switch
   to the new cluster as quickly as possible.
6. Once your traffic is fully migrated to the 0.10 cluster, decommission
   your 0.9 cluster.

## Upgrade to `0.9.x`

PostgreSQL is the new default datastore for Kong. If you were using Cassandra
and you are upgrading, you must explicitly set `cassandra` as your `database`.

This release introduces a new CLI, which uses the
[lua-resty-cli](https://github.com/openresty/resty-cli) interpreter. As such,
the `resty` executable (shipped in the OpenResty bundle) must be available in
your `$PATH`. Additionally, the `bin/kong` executable is not installed through
Luarocks anymore, and must be placed in your `$PATH` as well. This change of
behavior is taken care of if you are using one of the official Kong packages.

Once Kong updated, familiarize yourself with its new configuration format, and
consider setting some of its properties via environment variables if the need
arises. This behavior, as well as all available settings, are documented in the
`kong.conf.default` file shipped with this version.

Once your nodes configured, we recommend that you seemingly redirect your
traffic through the new Kong 0.9 nodes before decommissioning your old nodes.

## Upgrade to `0.8.x`

No important breaking changes for this release, just be careful to not use the
long deprecated routes `/consumers/:consumer/keyauth/` and
`/consumers/:consumer/basicauth/` as instructed in the Changelog. As always,
also make sure to check the configuration file for new properties (this release
allows you to configure the read/write consistency of Cassandra).

Let's talk about **PostgreSQL**. To use it instead of Cassandra, follow those
steps:

* Get your hands on a 9.4+ server (being compatible with Postgres 9.4 allows
  you to use [Amazon RDS](https://aws.amazon.com/rds/))
* Create a database, (maybe a user too?), let's say `kong`
* Update your Kong configuration:

```yaml
# as always, be careful about your YAML formatting
database: postgres
postgres:
  host: "127.0.0.1"
  port: 5432
  user: kong
  password: kong
  database: kong
```

As usual, migrations should run from kong start, but as a reminder and just in
case, here are some tips:

Reset the database with (careful, you'll lose all data):
```
$ kong migrations reset --config kong.yml
```

Run the migrations manually with:
```
$ kong migrations up --config kong.yml
```

If needed, list your migrations for debug purposes with:
```
$ kong migrations list --config kong.yml
```

**Note**: This release does not provide a mean to migrate from Cassandra to
PostgreSQL. Additionally, we recommend that you **do not** use `kong reload` if
you switch your cluster from Cassandra to PostgreSQL. Instead, we recommend
that you migrate by spawning a new cluster and gradually redirect your traffic
before decommissioning your old nodes.

## Upgrade to `0.7.x`

If you are running a source installation, you will need to upgrade OpenResty to
its `1.9.7.*` version. The good news is that this family of releases does not
need to patch the NGINX core anymore to enable SSL support. If you install Kong
from one of the distribution packages, they already include the appropriate
OpenResty, simply download and install the appropriate package for your
platform.

As described in the Changelog, this upgrade has benefits, such as the SSL
support and fixes for critical NGINX vulnerabilities, but also requires that
you upgrade the `nginx` property of your Kong config because it is not
backwards compatible.

- We advise that you retrieve the `nginx` property from the `0.7.x`
  configuration file, and use it in yours with the changes you feel are
  appropriate.

- Finally, you can reload Kong as usual:

```shell
$ kong reload [-c configuration_file]
```

**Note**: We expose the underlying NGINX configuration as a way for Kong to be
as flexible as possible and allow you to bend your NGINX instance to your
needs. We are aware that many of you do not need to customize it and such
changes should not affect you. Plans are to embed the NGINX configuration in
Kong, while still allowing customization for the most demanding users.
[#217](https://github.com/Kong/kong/pull/217) is the place to discuss this
and share thoughts/needs.

## Upgrade to `0.6.x`

**Note**: if you are using Kong 0.4.x or earlier, you must first upgrade to
Kong 0.5.x.

The configuration file changed in this release. Make sure to check out the new
default one and update it to your needs. In particular, make sure that:

```yaml
plugins_available:
  - key-auth
  - ...
  - custom-plugin
proxy_port: ...
proxy_ssl_port: ...
admin_api_port: ...
databases_available:
  cassandra:
    properties:
      contact_points:
        - ...
```

becomes:

```yaml
custom_plugins:
  - only-custom-plugins
proxy_listen: ...
proxy_listen_ssl: ...
admin_api_listen: ...
cassandra:
  contact_points:
    - ...
```

Secondly, if you installed Kong from source or maintain a development
installation, you will need to have [Serf](https://www.serfdom.io) installed on
your system and available in your `$PATH`. Serf is included with all the
distribution packages and images available at
[getkong.org/install](https://getkong.org/install/).

The same way, this should already be the case but make sure that LuaJIT is in
your `$PATH` too as the CLI interpreter switched from Lua 5.1 to LuaJIT.
Distribution packages also include LuaJIT.

In order to start Kong with its new clustering and cache invalidation
capabilities, you will need to restart your node(s) (and not reload):

```shell
$ kong restart [-c configuration_file]
```

Read more about the new clustering capabilities of Kong 0.6.0 and its
configurations in the [Clustering
documentation](https://getkong.org/docs/0.6.x/clustering/).

## Upgrade to `0.5.x`

Migrating to 0.5.x can be done **without downtime** by following those
instructions. It is important that you be running Kong `0.4.2` and have the
latest release of Python 2.7 on your system when executing those steps.

> Several changes were introduced in this version: some plugins and properties
> were renamed and the database schema slightly changed to introduce "plugins
> migrations". Now, each plugin can have its own migration if it needs to store
> data in your cluster. This is not a regular migration since the schema of the
> table handling the migrations itself changed.

##### 1. Configuration file

You will need to update your configuration file. Replace the
`plugins_available` values with:

```yaml
plugins_available:
  - ssl
  - jwt
  - acl
  - cors
  - oauth2
  - tcp-log
  - udp-log
  - file-log
  - http-log
  - key-auth
  - hmac-auth
  - basic-auth
  - ip-restriction
  - mashape-analytics
  - request-transformer
  - response-transformer
  - request-size-limiting
  - rate-limiting
  - response-ratelimiting
```

You can still remove plugins you don't use for a lighter Kong.

Also replace the Cassandra `hosts` property with `contact_points`:

```yaml
properties:
  contact_points:
    - "..."
    - "..."
  timeout: 1000
  keyspace: kong
  keepalive: 60000
```

##### 2. Migration script

[This Python
script](https://github.com/Kong/kong/blob/0.5.0/scripts/migration.py) will
take care of migrating your database schema should you execute the following
instructions:

```shell
# First, make sure you are already running Kong 0.4.2

# Clone the Kong git repository if you don't already have it:
$ git clone https://github.com/Kong/kong.git

# Go to the 'scripts/' folder:
$ cd kong/scripts

# Install the Python script dependencies:
$ pip install cassandra-driver==2.7.2 pyyaml

# The script will use the first Cassandra contact point in your Kong configuration file
# (the first of the 'contact_points' property) so make sure it is valid and has the format 'host:port'.

# Run the migration script:
$ python migration.py -c /path/to/kong/config
```

If everything went well the script should print a success message. **At this
point, your database is compatible with both Kong 0.4.2 and 0.5.x.** If you are
running more than one Kong node, you simply have to follow step 3. for each one
of them now.

##### 3. Upgrade without downtime

You can now upgrade Kong to `0.5.x.` Proceed as a regular upgrade and follow
the suggested upgrade path, in particular, the `kong reload` command.

##### 4. Purge your Cassandra cluster

Finally, once Kong has restarted in 0.5.x, run the migration script again, with
the `--purge` flag:

```shell
$ python migration.py -c /path/to/kong/config --purge
```

Your cluster is now fully migrated to `0.5.x`.

##### Other changes to acknowledge

Some entities and properties were renamed to avoid confusion:

- Properties belonging to APIs entities have been renamed for clarity:
  - `public_dns` -> `request_host`
  - `path` -> `request_path`
  - `strip_path` -> `strip_request_path`
  - `target_url` -> `upstream_url`
- `plugins_configurations` have been renamed to `plugins`, and their `value`
  property has been renamed to `config` to avoid confusions.
- The Key authentication and Basic authentication plugins routes have changed:

```
Old route                             New route
/consumers/:consumer/keyauth       -> /consumers/:consumer/key-auth
/consumers/:consumer/keyauth/:id   -> /consumers/:consumer/key-auth/:id
/consumers/:consumer/basicauth     -> /consumers/:consumer/basic-auth
/consumers/:consumer/basicauth/:id -> /consumers/:consumer/basic-auth/:id
```

The old routes are still maintained but will be removed in upcoming versions.
Consider them **deprecated**.

- Admin API:
  - The route to retrieve enabled plugins is now under `/plugins/enabled`.
  - The route to retrieve a plugin's configuration schema is now under
    `/plugins/schema/{plugin name}`.

## Upgrade to Kong `0.4.2`

The configuration format for specifying the port of your Cassandra instance
changed. Replace:

```yaml
cassandra:
  properties:
    hosts: "localhost"
    port: 9042
```

by:

```yaml
cassandra:
  properties:
    hosts:
      - "localhost:9042"
```

## Upgrade to `0.3.x`

Kong now requires a patch on OpenResty for SSL support. On Homebrew you will
need to reinstall OpenResty.

#### Homebrew

```shell
$ brew update
$ brew reinstall mashape/kong/ngx_openresty
$ brew upgrade kong
```

#### Troubleshoot

If you are seeing a similar error on `kong start`:

```
nginx: [error] [lua] init_by_lua:5: Startup error: Cassandra error: Failed to
prepare statement: "SELECT id FROM apis WHERE path = ?;". Cassandra returned
error (Invalid): "Undefined name path in where clause ('path = ?')"
```

You can run the following command to update your schema:

```
$ kong migrations up
```

Please consider updating to `0.3.1` or greater which automatically handles the
schema migration.
