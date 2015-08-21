This document describes eventual additional steps that might be required to update between two versions of Kong. If nothing is described here for a particular version and platform, then assume the update will go smoothly.

## Update to Kong `0.5.0`

It is important that you be running Kong `0.4.2` when executing those steps.

The database schema slightly changed to introduce "plugins migrations". Now, each plugin can have its own migration if it needs to store data in your cluster. This is not a regular migration since the schema of the table handling the migrations itself changed. This Python script will take care of migrating your database schema should you execute the following instructions:

```shell
# First, make sure you are already running Kong 0.4.2

# Download the new version of Kong.

# The script will use your first contact point (the first of the 'hosts' property)
# so make sure it is valid and has the format 'host:port'.

# Execute the migration script:
$ python migration.py -c /path/to/kong/config

# If everything went well the script should print a success message.

# Then, reload Kong to avoid downtime:
$ kong reload
```

Your cluster should successfully be migrated to Kong `0.5.0`.

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
