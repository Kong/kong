import { constants } from './constants';

export const vars = {
  aws: {
    AWS_ACCESS_KEY_ID: process.env.AWS_ACCESS_KEY_ID,
    AWS_SECRET_ACCESS_KEY: process.env.AWS_SECRET_ACCESS_KEY,
  },
  azure: {
    AZURE_FUNCTION_KEY:  process.env.AZURE_FUNCTION_KEY
  }
};
/**
 * Check that all necessary environment variables are defined before test execution
 * @param {string} scope - narrow down the scope to a specific set of variables e.g. azure or aws
 */
export const checkGwVars = (scope) => {
  const missingVars: string[] = [];
  for (const envVar in vars[scope]) {
    if (!vars[scope][envVar]) {
      missingVars.push(envVar);
    }
  }
  if (missingVars.length > 0) {
    throw new Error(
      `required gateway environment secrets not found: ${missingVars.join(
        ', '
      )}`
    );
  }
};

/**
 * Get current gateway host
 * @returns {string} - current gateway host
 */
export const getGatewayHost = (): string => {
  return process.env.GW_HOST || 'localhost';
};

/**
 * Check if current database is running in local mode
 * @returns {boolean} - true if the database is running in local mode else false
 */
export const isLocalDatabase = (): boolean => {
  return process.env.PG_IAM_AUTH == 'true' ? false : true;
};

/**
 * Get current gateway mode
 * @returns {string} - current gateway mode
 */
export const getGatewayMode = (): string => {
  return process.env.GW_MODE || 'classic';
};

/**
 * Check if current gateway mode is hybrid
 * @returns {boolean} - true if gateway runs in hybrid mode else false
 */
export const isGwHybrid = (): boolean => {
  return getGatewayMode() === 'hybrid' ? true : false;
};

/**
 * Check if gateway is installed natively (package tests)
 * @returns {boolean} - true if gateway is installed using a package
 */
export const isGwNative = (): boolean => {
  return process.env.KONG_PACKAGE ? true : false;
};

/**
 * Get running kong container name based on which test suite is running
 * @returns {string} - the name of the container
 */
export const getKongContainerName = (): string => {
  return process.env.KONG_PACKAGE ? process.env.KONG_PACKAGE : 'kong-cp';
};

/**
 * Get kong version
 * @returns {string} - the name of the container
 */
export const getKongVersion = (): string | undefined => {
  return process.env.KONG_VERSION;
};

/**
 * Get the target docker image for Konnect data plane, default is konnect-dp1
 * @returns {string}
 */
export const getDataPlaneDockerImage = (): string | undefined => {
  return process.env.KONNECT_DP_IMAGE ? process.env.KONNECT_DP_IMAGE : 'kong/kong-gateway-dev:nightly-ubuntu'
}

/**
 * Checks if GATEWAY_PASSWORD env var is set to return respective Auth header key:value
 */
export const gatewayAuthHeader = () => {
  return {
    authHeaderKey: constants.gateway.ADMIN_AUTH_HEADER,
    authHeaderValue: constants.gateway.ADMIN_PASSWORD,
  };
};
