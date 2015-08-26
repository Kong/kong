This document describes eventual additional steps that might be required to update between two versions of Kong. If nothing is described here for a particular version and platform, then assume the update will go smoothly.

## Update to Kong `0.5.0`

It is important that you be running Kong `0.4.2` and have the latest release of Python 2.7 on your system when executing those steps.

Several changes were introduced in this version: many plugins were renamed and the database schema slightly changed to introduce "plugins migrations". Now, each plugin can have its own migration if it needs to store data in your cluster. This is not a regular migration since the schema of the table handling the migrations itself changed.

##### 1. Migration script

[This Python script](/scripts/migration.py) will take care of migrating your database schema should you execute the following instructions:

```shell
# First, make sure you are already running Kong 0.4.2

# Clone the Kong git repository if you don't already have it:
$ git clone git@github.com:Mashape/kong.git

# Go to the 'scripts/' folder:
$ cd kong/scripts

# Install the Python script dependencies:
$ pip install cassandra-driver pyyaml

# The script will use your first contact point (the first of the 'hosts' property)
# so make sure it is valid and has the format 'host:port'.

# Execute the migration script:
$ python migration.py -c /path/to/kong/config

# If everything went well the script should print a success message.
```

##### 2. Configuration file

You will now need to update your configuration file. Replace the `plugins_available` property with:

```yaml
plugins_available:
  - ssl
  - key-auth
  - basic-auth
  - oauth2
  - rate-limiting
  - response-ratelimiting
  - tcp-log
  - udp-log
  - file-log
  - http-log
  - cors
  - request-transformer
  - response-transformer
  - request-size-limiting
  - ip-restriction
  - mashape-analytics
```

You can still remove plugins you don't use for a lighter Kong.

##### 3. Upgrade without downtime

You can now update Kong to 0.5.0. Proceed as a regular update and install the package of your choice from the website. After updating, reload Kong to avoid downtime:

```shell
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
