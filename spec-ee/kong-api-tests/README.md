# KONG API TESTS

[![Gateway API Tests](https://github.com/Kong/kong-ee/actions/workflows/gateway-api-tests.yml/badge.svg)](https://github.com/Kong/kong-ee/actions/workflows/gateway-api-tests.yml)

> Note: This repo is in active development.

The `spec-ee/kong-api-tests` is aimed to be used to create and execute Kong Gateway API tests locally as well as in CI.

### How to Build

1. Navigate to `spec-ee/kong-api-tests`
2. Install `node` & `npm` (you can also use [nvm](https://github.com/nvm-sh/nvm)) (minimum node.js version `v16.x.x`)
3. Access private NPM packages
   - Copy `.npmrc.ci` file contents into `.npmrc`
     - `cp .npmrc.ci .npmrc`
   - Export the `NPM_TOKEN` in your terminal
     - `export NPM_TOKEN=`[NPM Read Token](https://start.1password.com/open/i?a=KJVYOL2OTVGRPAAAHEVOL6MXZE&h=team-kong.1password.com&i=ss3ux3i3brfsruiarhhugzlqqm&v=q7r4hh4465zentymwtoonxxp3m)
4. For formatting/linting, run `npm run format` and then `npm run lint`
5. Install the dependency packages with the following command `npm install --legacy-peer-deps`

## Gateway

**Deploying Gateway**

We use [gateway-docker-compose-generator](https://github.com/Kong/gateway-docker-compose-generator) to deploy gateway for API tests.\
In CI, the gateway starts `without enterprise license`. The license is being posted via API at the runtime before all tests to allow us to have more control over the license.

### Env File

Create a `.env` file in the root directory.

Copy from the [.env.example](https://github.com/Kong/kong-api-tests/blob/contrib/readme-update/.env.example.gateway) file.

Add the following gateway specific environment variable to your `.env` file.

TEST_APP=gateway

**Environment Secrets**

Retrieve the necessary credentials from _1Password_ and add as environment variables in your .env file:

- [AWS Secret Credentials](https://start.1password.com/open/i?a=KJVYOL2OTVGRPAAAHEVOL6MXZE&v=q7r4hh4465zentymwtoonxxp3m&i=3o5zhzexnfhyldid53j6fquvwm&h=team-kong.1password.com) - required only for `aws-lambda-secret-reference` test

  `AWS_ACCESS_KEY_ID="<aws_access_key_id>"`

  `AWS_SECRET_ACCESS_KEY="<aws_secret_access_key>"`

**Test specific environment variable requirements for Gateway**

There are tests which rely on specific gateway environment variables, make sure to include these in your gateway/kong/docker.

- `aws-lambda-secret-reference` test

  `AWS_REGION="us-east-2"`

  `AWS_ACCESS_KEY_ID="<aws_access_key_id>"`

  `AWS_SECRET_ACCESS_KEY="<aws_secret_access_key>"`

  [GCP_SERVICE_ACCOUNT](https://start.1password.com/open/i?a=KJVYOL2OTVGRPAAAHEVOL6MXZE&v=q7r4hh4465zentymwtoonxxp3m&i=w2gvxcep5ffevmiykbfq4ffb64&h=team-kong.1password.com)`="<gcp_service_account_key>"`
- `azure-functions-secret-reference` test

  [AZURE_FUNCTION_KEY](https://start.1password.com/open/i?a=KJVYOL2OTVGRPAAAHEVOL6MXZE&v=q7r4hh4465zentymwtoonxxp3m&i=e7vip43g3nucwsrb44ijs6qsfa&h=team-kong.1password.com)`="<azure_function_key>"`

- `rla-secret-referene` test

  `RLA_REDISU=redisuser`

  `RLA_REDISP=redispassword`

  `AWS_REGION="us-east-2"`

  `AWS_ACCESS_KEY_ID="<aws_access_key_id>"`

  `AWS_SECRET_ACCESS_KEY="<aws_secret_access_key>"`

  [GCP_SERVICE_ACCOUNT](https://start.1password.com/open/i?a=KJVYOL2OTVGRPAAAHEVOL6MXZE&v=q7r4hh4465zentymwtoonxxp3m&i=w2gvxcep5ffevmiykbfq4ffb64&h=team-kong.1password.com)`="<gcp_service_account_key>"`

## Test specific 3rd party service requirements for Gateway

There are specific tests which rely on particular 3rd party services to run alongside the gateway.\
Make sure to enable these services using [gateway-docker-compose-generator](https://eu.api.konghq.com/konnect-api)

- All tests relying in upstream service or sending requests to upstream use [httpbin-service](https://github.com/Kong/gateway-docker-compose-generator/blob/ce44aa5d508b7210336a58975285ea8e2e6b6bee/docker-compose.yml.sh#L211) which needs to run in the same docker network as kong. 
- `1_vitals-influxdb` test requires [INFLUXDB](https://github.com/Kong/gateway-docker-compose-generator/blob/d9ee692675d4efdb14d0e1b8376b20a290f72b34/docker-compose.yml.sh#L32)
- `aws-lambda-secret-reference` and `rla-secret-reference` tests require [HCV](https://github.com/Kong/gateway-docker-compose-generator/blob/d9ee692675d4efdb14d0e1b8376b20a290f72b34/docker-compose.yml.sh#L40)
- `opentelemtry` test requires [JAEGER](https://github.com/Kong/gateway-docker-compose-generator/blob/d9ee692675d4efdb14d0e1b8376b20a290f72b34/docker-compose.yml.sh#L54)
- `rate-limiting-advanced` test requires [REDIS (standalone)](https://github.com/Kong/gateway-docker-compose-generator/blob/d9ee692675d4efdb14d0e1b8376b20a290f72b34/docker-compose.yml.sh#L29)
- `oas-validation` test requires [SWAGGER](https://github.com/Kong/gateway-docker-compose-generator/blob/main/docker-compose.yml.sh#L36)

**Test specific configuration requirements for Gateway**

- `licenses` test requires the gateway to NOT have enterprise license. We `post` the enterprise license at the runtime via API before tests start to run.\
  There will be no harm having the license in kong, the tests will still pass but in order to fully imitate the CI environment you need to set `CI=true` and exclude license from kong locally.

**Gateway Mode**

The default Gateway mode is `classic`. If you want to run tests against `hybrid` mode specify that in your `.env` file:

```bash
# .env file
GW_MODE=hybrid
```

### Verbose Response Logging

`export VERBOSE_RESPONSE_LOGS=false` to disable response logging (default is `true`).

**Execute Gateway API Test Suites**

- All existing gateway test

```bash
npm run test-gateway
```

- A single gateway test

```bash
# for example if you want to run 'service.spec.ts' tests
npm run test-spec --spec=service
```

- Smoke tests

```bash
npm run test-smoke
```

- Release package tests

Make sure to have `KONG_VERSION` and `KONG_PACKAGE` variables set in your environment.\
For example, `export KONG_PACKAGE=ubuntu-22.04 KONG_VERSION=3.3.0.0` or in your `.env` file

**When `KONG_PACKAGE` environment variable is set in your environment the framework will automatically\
understand that api tests should run against natively installed kong (download kong from pulp and install).**
After this, you can run the tests as mentioned above.

Refer to [How to run API smoke tests](https://konghq.atlassian.net/wiki/spaces/FTT/pages/3072917606/Running+smoke+tests+on+released+artifacts) to learn about running the tests in GH Actions.


## Koko & Konnect

### Env File

Add the following konnect specific environment variables to your `.env` file.

1. TEST_APP=koko
2. TEST_ENV=dev
3. KONNECT_USER_PASSWORD=[KONNECT_USER_PASSWORD](https://start.1password.com/open/i?a=KJVYOL2OTVGRPAAAHEVOL6MXZE&v=q7r4hh4465zentymwtoonxxp3m&i=vag6ska5nafl3u7rlxy26wobge&h=team-kong.1password.com)
4. KONNECT_DP_IMAGE=`yourTargetDockerImage` - optional, default is kong/kong-gateway-dev:nightly-ubuntu

**Execute Konnect Tests**

- All existing tests

```bash
npm run test-koko
```
- A single test

```bash
# for example if you want to run 'service.spec.ts' tests
npm run test-spec --spec=service
```