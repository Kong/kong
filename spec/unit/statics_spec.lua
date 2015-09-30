local spec_helper = require "spec.spec_helpers"
local constants = require "kong.constants"
local stringy = require "stringy"
local IO = require "kong.tools.io"
local fs = require "luarocks.fs"

describe("Static files", function()
  describe("Constants", function()
    it("version set in constants should match the one in the rockspec", function()
      local rockspec_path
      for _, filename in ipairs(fs.list_dir(".")) do
        if stringy.endswith(filename, "rockspec") then
          rockspec_path = filename
          break
        end
      end

      if not rockspec_path then
        error("Can't find the rockspec file")
      end

      local file_content = IO.read_file(rockspec_path)
      local res = file_content:match("\"+[0-9.-]+[a-z]*[0-9-]*\"+")
      local extracted_version = res:sub(2, res:len() - 1)
      assert.are.same(constants.ROCK_VERSION, extracted_version)

      local dash = string.find(extracted_version, "-")
      assert.are.same(constants.VERSION, dash and extracted_version:sub(1, dash - 1) or extracted_version)
    end)

    it("accessing non-existing error code should throw an error", function()
      assert.has_no_error(function() local _ = constants.DATABASE_ERROR_TYPES.DATABASE end)
      assert.has_error(function() local _ = constants.DATABASE_ERROR_TYPES.ThIs_TyPe_DoEs_NoT_ExIsT end)
    end)
  end)

  describe("Configuration", function()

    it("should equal to this template to make sure no errors are pushed in the default config", function()
      local configuration = IO.read_file(spec_helper.DEFAULT_CONF_FILE)

      assert.are.same([[
## Available plugins on this server
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

## The Kong working directory
## (Make sure you have read and write permissions)
nginx_working_dir: /usr/local/kong/

## Port configuration
proxy_port: 8000
proxy_ssl_port: 8443
admin_api_port: 8001

## Secondary port configuration
dnsmasq_port: 8053

## Specify the DAO to use
database: cassandra

## Databases configuration
databases_available:
  cassandra:
    properties:
      contact_points:
        - "localhost:9042"
      timeout: 1000
      keepalive: 60000 # in milliseconds
      keyspace: kong

      ## Keyspace options. Set those before running Kong or any migration.
      ## Those settings will be used to create a keyspace with the desired options
      ## when first running the migrations.
      ##
      ## See http://docs.datastax.com/en/cql/3.1/cql/cql_reference/create_keyspace_r.html

      ## The name of the replica placement strategy class for the new keyspace.
      ## Can be "SimpleStrategy" or "NetworkTopologyStrategy".
      replication_strategy: SimpleStrategy

      ## For SimpleStrategy only.
      ## The number of replicas of data on multiple nodes.
      replication_factor: 1

      ## For NetworkTopologyStrategy only.
      ## The number of replicas of data on multiple nodes in each data center.
      # data_centers:
      #   dc1: 2
      #   dc2: 3

      ## SSL client-to-node encryption and authentication options.
      # ssl: false
      # ssl_verify: false
      # ssl_certificate: "/path/to/cluster-ca-certificate.pem"
      # user: cassandra
      # password: cassandra

## Cassandra cache configuration
database_cache_expiration: 5 # in seconds

## SSL Settings
## (Uncomment the two properties below to set your own certificate)
# ssl_cert_path: /path/to/certificate.pem
# ssl_key_path: /path/to/certificate.key

## Sends anonymous error reports
send_anonymous_reports: true

## In-memory cache size (MB)
memory_cache_size: 128

## Nginx configuration
nginx: |
  worker_processes auto;
  error_log logs/error.log error;
  daemon on;

  worker_rlimit_nofile {{auto_worker_rlimit_nofile}};

  env KONG_CONF;

  events {
    worker_connections {{auto_worker_connections}};
    multi_accept on;
  }

  http {
    resolver {{dns_resolver}} ipv6=off;
    charset UTF-8;

    access_log logs/access.log;
    access_log off;

    # Timeouts
    keepalive_timeout 60s;
    client_header_timeout 60s;
    client_body_timeout 60s;
    send_timeout 60s;

    # Proxy Settings
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;
    proxy_ssl_server_name on;

    # IP Address
    real_ip_header X-Forwarded-For;
    set_real_ip_from 0.0.0.0/0;
    real_ip_recursive on;

    # Other Settings
    client_max_body_size 0;
    underscores_in_headers on;
    reset_timedout_connection on;
    tcp_nopush on;

    ################################################
    #  The following code is required to run Kong  #
    # Please be careful if you'd like to change it #
    ################################################

    # Lua Settings
    lua_package_path ';;';
    lua_code_cache on;
    lua_max_running_timers 4096;
    lua_max_pending_timers 16384;
    lua_shared_dict locks 100k;
    lua_shared_dict cache {{memory_cache_size}}m;
    lua_socket_log_errors off;
    {{lua_ssl_trusted_certificate}}

    init_by_lua '
      kong = require "kong"
      local status, err = pcall(kong.init)
      if not status then
        ngx.log(ngx.ERR, "Startup error: "..err)
        os.exit(1)
      end
    ';

    init_worker_by_lua 'kong.exec_plugins_init_worker()';

    server {
      server_name _;
      listen {{proxy_port}};
      listen {{proxy_ssl_port}} ssl;

      ssl_certificate_by_lua 'kong.exec_plugins_certificate()';

      ssl_certificate {{ssl_cert}};
      ssl_certificate_key {{ssl_key}};
      ssl_protocols TLSv1 TLSv1.1 TLSv1.2;# omit SSLv3 because of POODLE (CVE-2014-3566)

      location / {
        default_type 'text/plain';

        # These properties will be used later by proxy_pass
        set $backend_host nil;
        set $backend_url nil;

        # Authenticate the user and load the API info
        access_by_lua 'kong.exec_plugins_access()';

        # Proxy the request
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $backend_host;
        proxy_pass $backend_url;
        proxy_pass_header Server;

        # Add additional response headers
        header_filter_by_lua 'kong.exec_plugins_header_filter()';

        # Change the response body
        body_filter_by_lua 'kong.exec_plugins_body_filter()';

        # Log the request
        log_by_lua 'kong.exec_plugins_log()';
      }

      location /robots.txt {
        return 200 'User-agent: *\nDisallow: /';
      }

      error_page 500 /500.html;
      location = /500.html {
        internal;
        content_by_lua '
          local responses = require "kong.tools.responses"
          responses.send_HTTP_INTERNAL_SERVER_ERROR("An unexpected error occurred")
        ';
      }
    }

    server {
      listen {{admin_api_port}};

      location / {
        default_type application/json;
        content_by_lua '
          ngx.header["Access-Control-Allow-Origin"] = "*"
          if ngx.req.get_method() == "OPTIONS" then
            ngx.header["Access-Control-Allow-Methods"] = "GET,HEAD,PUT,PATCH,POST,DELETE"
            ngx.header["Access-Control-Allow-Headers"] = "Content-Type"
            ngx.exit(204)
          end
          local lapis = require "lapis"
          lapis.serve("kong.api.app")
        ';
      }

      location /nginx_status {
        internal;
        stub_status;
      }

      location /robots.txt {
        return 200 'User-agent: *\nDisallow: /';
      }

      # Do not remove, additional configuration placeholder for some plugins
      # {{additional_configuration}}
    }
  }
]], configuration)
    end)

  end)
end)
