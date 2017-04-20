This document guides you through the process of upgrading Kong. First, check if
a section named "Upgrade to Kong `x.x.x`" exists, with `x.x.x` being the version
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
[reload](https://getkong.org/docs/latest/cli/#reload) Kong:

```shell
$ kong reload [-c configuration_file]
```

**Reminder**: `kong reload` leverages the Nginx `reload` signal that seamlessly
starts new workers, which take over from old workers before those old workers
are terminated. In this way, Kong will serve new requests via the new
configuration, without dropping existing in-flight connections.

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
- Dynamic SSL certificates serving is now handled by the core, and **not**
  through the `ssl` plugin anymore. This version introduced the `/certificates`
  and `/snis` endpoints.  See the new [0.10 Proxy
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

We recommend that you consult the full [0.10.0
Changelog](https://github.com/Mashape/kong/blob/master/CHANGELOG.md) for a full
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
your `$PATH`.  Additionally, the `bin/kong` executable is not installed through
Luarocks anymore, and must be placed in your `$PATH` as well.  This change of
behavior is taken care of if you are using one of the official Kong packages.

Once Kong updated, familiarize yourself with its new configuration format, and
consider setting some of its properties via environment variables, if the need
arises. This behavior as well as all available settings are documented in the
`kong.conf.default` file shipped with this version.

Once your nodes configured, we recommend that you seamingly redirect your
traffic through the new Kong 0.9 nodes before decomissioning your old nodes.

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
before decomissioning your old nodes.

## Upgrade to `0.7.x`

If you are running a source installation, you will need to upgrade OpenResty to
its `1.9.7.*` version. The good news is that this family of releases does not
need to patch the NGINX core anymore to enable SSL support. If you install Kong
from one of the distribution packages, they already include the appropriate
OpenResty, simply download and install the appropriate package for your
platform.

As described in the Changelog, this upgrade has benefits, such as the SSL
support and fixes for critical NGINX vulnerabilities, but also requires that
you upgrade the `nginx` property of your Kong config, because it is not
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
[#217](https://github.com/Mashape/kong/pull/217) is the place to discuss this
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
script](https://github.com/Mashape/kong/blob/0.5.0/scripts/migration.py) will
take care of migrating your database schema should you execute the following
instructions:

```shell
# First, make sure you are already running Kong 0.4.2

# Clone the Kong git repository if you don't already have it:
$ git clone https://github.com/Mashape/kong.git

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
the suggested upgrade path, in particular the `kong reload` command.

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
