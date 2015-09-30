This document describes eventual additional steps that might be required to update between two versions of Kong. If nothing is described here for a particular version and platform, then assume the update will go smoothly.

## Update to Kong `0.5.0`

Migrating to 0.5.0 can be done **without downtime** by following those instructions. It is important that you be running Kong `0.4.2` and have the latest release of Python 2.7 on your system when executing those steps.

> Several changes were introduced in this version: some plugins and properties were renamed and the database schema slightly changed to introduce "plugins migrations". Now, each plugin can have its own migration if it needs to store data in your cluster. This is not a regular migration since the schema of the table handling the migrations itself changed.

##### 1. Configuration file

You will need to update your configuration file. Replace the `plugins_available` values with:

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

[This Python script](/scripts/migration.py) will take care of migrating your database schema should you execute the following instructions:

```shell
# First, make sure you are already running Kong 0.4.2

# Clone the Kong git repository if you don't already have it:
$ git clone git@github.com:Mashape/kong.git

# Go to the 'scripts/' folder:
$ cd kong/scripts

# Install the Python script dependencies:
$ pip install cassandra-driver pyyaml

# The script will use the first Cassandra contact point in your Kong configuration file
# (the first of the 'contact_points' property) so make sure it is valid and has the format 'host:port'.

# Run the migration script:
$ python migration.py -c /path/to/kong/config
```

If everything went well the script should print a success message. **At this point, your database is compatible with both Kong 0.4.2 and 0.5.0.** If you are running more than one Kong node, you simply have to follow step 3. for each one of them now.

##### 3. Upgrade without downtime

You can now update Kong to 0.5.0. Proceed as a regular update and install the package of your choice from the website. After updating, reload Kong to avoid downtime:

```shell
$ kong reload
```

##### 4. Purge your Cassandra cluster

Finally, once Kong has restarted in 0.5.0, run the migration script again, with the `--purge` flag:

```shell
$ python migration.py -c /path/to/kong/config --purge
```

Your cluster is now fully migrated to `0.5.0`.

##### Other changes to acknowledge

Some entities and properties were renamed to avoid confusion:

- `public_dns` and `target_url` properties of APIs were respectively renamed to `request_host` and `upstream_url`.
- Properties belonging to APIs entities have been renamed for clarity:
  - `public_dns` -> `request_host`
  - `path` -> `request_path`
  - `strip_path` -> `strip_request_path`
  - `target_url` -> `upstream_url`
- `plugins_configurations` have been renamed to `plugins`, and their `value` property has been renamed to `config` to avoid confusions.
- The Key authentication and Basic authentication plugins routes have changed:

```
Old route                             New route
/consumers/:consumer/keyauth       -> /consumers/:consumer/key-auth
/consumers/:consumer/keyauth/:id   -> /consumers/:consumer/key-auth/:id
/consumers/:consumer/basicauth     -> /consumers/:consumer/basic-auth
/consumers/:consumer/basicauth/:id -> /consumers/:consumer/basic-auth/:id
```

The old routes are still maintained but will be removed in upcoming versions. Consider them **deprecated**.

- Admin API:
  - The route to retrieve enabled plugins is now under `/plugins/enabled`.
  - The route to retrieve a plugin's configuration schema is now under `/plugins/schema/{plugin name}`.

## Update to Kong `0.4.2`

The configuration format for specifying the port of your Cassandra instance changed. Replace:

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

## Update to Kong `0.3.x`

Kong now requires a patch on OpenResty for SSL support. On Homebrew you will need to reinstall OpenResty.

#### Homebrew

```shell
$ brew update
$ brew reinstall mashape/kong/ngx_openresty
$ brew upgrade kong
```

#### Troubleshoot

If you are seeing a similar error on `kong start`:

```
nginx: [error] [lua] init_by_lua:5: Startup error: Cassandra error: Failed to prepare statement: "SELECT id FROM apis WHERE path = ?;". Cassandra returned error (Invalid): "Undefined name path in where clause ('path = ?')"
```

You can run the following command to update your schema:

```
$ kong migrations up
```

Please consider updating to `0.3.1` or greater which automatically handles the schema migration.
