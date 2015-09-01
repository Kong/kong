#!/usr/bin/env python

'''Kong 0.5.0 Migration Script

Usage: python migration.py --config=/path/to/kong/config [--purge]

Run this script first to migrate Kong to the 0.5.0 schema. Once successful, reload Kong
and run this script again with the --purge option.

Arguments:
  -c, --config   path to your Kong configuration file
Flags:
  --purge    if already migrated, purge the old values
  -h             print help
'''

import getopt, sys, os.path, logging, json

log = logging.getLogger()
log.setLevel("INFO")
handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter("[%(levelname)s]: %(message)s"))
log.addHandler(handler)

try:
    import yaml
    from cassandra.cluster import Cluster
    from cassandra import ConsistencyLevel, InvalidRequest
    from cassandra.query import SimpleStatement
except ImportError as err:
    log.error(err)
    log.info("""This script requires cassandra-driver and PyYAML:
    $ pip install cassandra-driver pyyaml""")
    sys.exit(1)

session = None

class ArgumentException(Exception):
    pass

def usage():
    """
    Print usage informations about this script.
    """
    print sys.exit(__doc__)

def shutdown_exit(exit_code):
    """
    Shutdown the Cassandra session and exit the script.
    """
    session.shutdown()
    sys.exit(exit_code)

def load_cassandra_config(kong_config):
    """
    Return a host and port from the first contact point in the Kong configuration.

    :param kong_config: parsed Kong configuration
    :return: host and port tuple
    """
    cass_properties = kong_config["databases_available"]["cassandra"]["properties"]

    host, port = cass_properties["contact_points"][0].split(":")
    keyspace = cass_properties["keyspace"]

    return (host, port, keyspace)

def migrate_schema_migrations_table(session):
    """
    Migrate the schema_migrations table whose values changed between < 0.5.0 and 0.5.0

    :param session: opened cassandra session
    """
    log.info("Migrating schema_migrations table...")
    query = SimpleStatement("INSERT INTO schema_migrations(id, migrations) VALUES(%s, %s)", consistency_level=ConsistencyLevel.ALL)
    session.execute(query, ["core", ['2015-01-12-175310_skeleton', '2015-01-12-175310_init_schema']])
    session.execute(query, ["basic-auth", ['2015-08-03-132400_init_basicauth']])
    session.execute(query, ["key-auth", ['2015-07-31-172400_init_keyauth']])
    session.execute(query, ["rate-limiting", ['2015-08-03-132400_init_ratelimiting']])
    session.execute(query, ["oauth2", ['2015-08-03-132400_init_oauth2', '2015-08-24-215800_cascade_delete_index']])
    log.info("schema_migrations table migrated")

def migrate_plugins_configurations(session):
    """
    Migrate all rows in the `plugins_configurations` table to `plugins`, applying:
    - renaming of plugins if name changed
    - conversion of old rate-limiting schema if old schema detected

    :param session: opened cassandra session
    """
    log.info("Migrating plugins...")

    new_names = {
        "keyauth": "key-auth",
        "basicauth": "basic-auth",
        "ratelimiting": "rate-limiting",
        "tcplog": "tcp-log",
        "udplog": "udp-log",
        "filelog": "file-log",
        "httplog": "http-log",
        "request_transformer": "request-transformer",
        "response_transfomer": "response-transfomer",
        "requestsizelimiting": "request-size-limiting",
        "ip_restriction": "ip-restriction"
    }

    session.execute("""
       create table if not exists plugins(
          id uuid,
          api_id uuid,
          consumer_id uuid,
          name text,
          config text,
          enabled boolean,
          created_at timestamp,
          primary key (id, name))""")
    session.execute("create index if not exists on plugins(name)")
    session.execute("create index if not exists on plugins(api_id)")
    session.execute("create index if not exists on plugins(consumer_id)")

    for plugin in session.execute("SELECT * FROM plugins_configurations"):
        # New plugins names
        plugin_name = plugin.name
        if plugin.name in new_names:
            plugin_name = new_names[plugin.name]

        # rate-limiting config
        plugin_conf = plugin.value
        if plugin_name == "rate-limiting":
            conf = json.loads(plugin.value)
            if "limit" in conf:
                plugin_conf = {}
                plugin_conf[conf["period"]] = conf["limit"]
                plugin_conf = json.dumps(plugin_conf)

        insert_query = SimpleStatement("""
            INSERT INTO plugins(id, api_id, consumer_id, name, config, enabled, created_at)
            VALUES(%s, %s, %s, %s, %s, %s, %s)""", consistency_level=ConsistencyLevel.ALL)
        session.execute(insert_query, [plugin.id, plugin.api_id, plugin.consumer_id, plugin_name, plugin_conf, plugin.enabled, plugin.created_at])

    log.info("Plugins migrated")

def migrate_rename_apis_properties(sessions):
    """
    Create new columns for the `apis` column family and insert the equivalent values in it

    :param session: opened cassandra session
    """
    log.info("Renaming some properties for APIs...")

    session.execute("ALTER TABLE apis ADD inbound_dns text")
    session.execute("ALTER TABLE apis ADD upstream_url text")
    session.execute("CREATE INDEX IF NOT EXISTS ON apis(inbound_dns)")

    select_query = SimpleStatement("SELECT * FROM apis", consistency_level=ConsistencyLevel.ALL)

    for api in session.execute(select_query):
        session.execute("UPDATE apis SET inbound_dns = %s, upstream_url = %s WHERE id = %s", [api.public_dns, api.target_url, api.id])

    log.info("APIs properties renamed")

def purge(session):
    session.execute("ALTER TABLE apis DROP public_dns")
    session.execute("ALTER TABLE apis DROP target_url")
    session.execute("DROP TABLE plugins_configurations")
    session.execute("DELETE FROM schema_migrations WHERE id = 'migrations'")

def migrate(session):
    migrate_schema_migrations_table(session)
    migrate_plugins_configurations(session)
    migrate_rename_apis_properties(session)

def parse_arguments(argv):
    """
    Parse the scripts arguments.

    :param argv: scripts arguments
    :return: parsed kong configuration
    """
    config_path = ""
    purge = False

    opts, args = getopt.getopt(argv, "hc:", ["config=", "purge"])
    for opt, arg in opts:
        if opt == "-h":
            usage()
        elif opt in ("-c", "--config"):
            config_path = arg
        elif opt in ("--purge"):
            purge = True

    if config_path == "":
        raise ArgumentException("No Kong configuration given")
    elif not os.path.isfile(config_path):
        raise ArgumentException("No configuration file at path %s" % str(arg))

    log.info("Using Kong configuration file at: %s" % os.path.abspath(config_path))

    with open(config_path, "r") as stream:
        config = yaml.load(stream)

    return (config, purge)

def main(argv):
    try:
        kong_config, purge_cmd = parse_arguments(argv)
        host, port, keyspace = load_cassandra_config(kong_config)
        cluster = Cluster([host], protocol_version=2, port=port)
        global session
        session = cluster.connect(keyspace)

        # Find out where the schema is at
        rows = session.execute("SELECT * FROM schema_migrations")
        is_migrated = len(rows) > 1 and any(mig.id == "core" for mig in rows)
        is_0_4_2 = len(rows) == 1 and rows[0].migrations[-1] == "2015-08-10-813213_0.4.2"
        is_purged = len(session.execute("SELECT * FROM system.schema_columnfamilies WHERE keyspace_name = %s AND columnfamily_name = 'plugins_configurations'", [keyspace])) == 0

        if not is_0_4_2 and not is_migrated:
            log.error("Please migrate your cluster to Kong 0.4.2 before running this script.")
            shutdown_exit(1)

        if purge_cmd :
            if not is_purged and is_migrated:
                purge(session)
                log.info("Cassandra purged from <0.5.0 data")
            elif not is_purged and not is_migrated:
                log.info("Cassandra not previously migrated. Run this script in migration mode before.")
                shutdown_exit(1)
            else:
                log.info("Cassandra already purged and migrated")
        elif not is_migrated:
            migrate(session)
            log.info("Cassandra migrated to Kong 0.5.0.")
        else:
            log.info("Cassandra already migrated to Kong 0.5.0")

        shutdown_exit(0)
    except getopt.GetoptError as err:
        log.error(err)
        usage()
    except ArgumentException as err:
        log.error("Bad argument: %s " % err)
        usage()
    except yaml.YAMLError as err:
        log.error("Cannot parse given configuration file: %s" % err)
        sys.exit(1)

if __name__ == "__main__":
    main(sys.argv[1:])
