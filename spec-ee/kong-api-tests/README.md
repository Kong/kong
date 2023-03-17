# KONG API TESTS

[![Gateway API Tests](https://github.com/Kong/kong-api-tests/actions/workflows/gateway.yml/badge.svg)](https://github.com/Kong/kong-api-tests/actions/workflows/gateway.yml)

> Note: This repo is in active development.

This respository is aimed to be used to create and execute Kong API tests locally as well as in CI runs.

### How to Build

1. Install `node` & `npm` (e.g. you can use [nvm](https://github.com/nvm-sh/nvm)) (minimum version `v16.x.x`)
2. Copy `.npmrc.ci` file contents into `.npmrc` - in your terminal run `cp .npmrc.ci .npmrc`
3. export `NPM_TOKEN` in your terminal. [Npm Publish Token](https://start.1password.com/open/i?a=KJVYOL2OTVGRPAAAHEVOL6MXZE&h=team-kong.1password.com&i=ss3ux3i3brfsruiarhhugzlqqm&v=q7r4hh4465zentymwtoonxxp3m)
4. Run `npm install`
5. For formatting/linting, run `npm run format` and then `npm run lint`

### Verbose Response Logging

`export VERBOSE_RESPONSE_LOGS=false` to disable response logging (default is `true`).

## Gateway

**Deploying Gateway**

We use [gateway-docker-compose-generator](https://github.com/Kong/gateway-docker-compose-generator) to deploy gateway for API tests.\
In CI, the gateway starts `without enterprise license`. The license is being posted via API at the runtime before all tests to allow us to have more control over the license.


### Env File

Create a `.env` file in the root directory.

Copy from the [.env.example](https://github.com/Kong/kong-api-tests/blob/contrib/readme-update/.env.example.gateway) file.

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

- `rla-secret-referene` test

  `RLA_REDISU=redisuser`

  `RLA_REDISP=redispassword`

  `AWS_REGION="us-east-2"`

  `AWS_ACCESS_KEY_ID="<aws_access_key_id>"`

  `AWS_SECRET_ACCESS_KEY="<aws_secret_access_key>"`

  [GCP_SERVICE_ACCOUNT](https://start.1password.com/open/i?a=KJVYOL2OTVGRPAAAHEVOL6MXZE&v=q7r4hh4465zentymwtoonxxp3m&i=w2gvxcep5ffevmiykbfq4ffb64&h=team-kong.1password.com)`="<gcp_service_account_key>"`

**Test specific 3rd party service requirements for Gateway**

There are specific tests which rely on particular 3rd party services to run alongside the gateway.\
Make sure to enable these services using [gateway-docker-compose-generator](https://eu.api.konghq.com/konnect-api)

- `1_vitals-influxdb` test requires [INFLUXDB](https://github.com/Kong/gateway-docker-compose-generator/blob/d9ee692675d4efdb14d0e1b8376b20a290f72b34/docker-compose.yml.sh#L32)
- `aws-lambda-secret-reference` and `rla-secret-reference` tests require [HCV](https://github.com/Kong/gateway-docker-compose-generator/blob/d9ee692675d4efdb14d0e1b8376b20a290f72b34/docker-compose.yml.sh#L40)
- `opentelemtry` test requires [JAEGER](https://github.com/Kong/gateway-docker-compose-generator/blob/d9ee692675d4efdb14d0e1b8376b20a290f72b34/docker-compose.yml.sh#L54)

**Test specific configuration requirements for Gateway**

- `licenses` test requires the gateway to NOT have enterprise license. We `post` the enterprise license at the runtime via API before tests start to run.\
  There will be no harm having the license in kong, the tests will still pass but in order to fully imitate the CI environment you need to set `CI=true` and exclude license from kong locally.

**Gateway Mode**

The default Gateway mode is `classic`. If you want to run tests against `hybrid` mode specify that in your `.env` file:

```bash
# .env file
GW_MODE=hybrid
```

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
