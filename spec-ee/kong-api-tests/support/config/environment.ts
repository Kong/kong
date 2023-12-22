import { getGatewayHost } from './gateway-vars';
import { getApiGeo } from './geos';
import { getRuntimeGroupId } from '../entities/runtimes';

/**
 * Enum of available envs
 */
export enum Env {
  dev = 'dev',
  prod = 'prod',
}

/**
 * Enum of available apps
 */
export enum App {
  gateway = 'gateway',
  koko = 'koko',
  kauth = 'kauth',
  kauth_v2 = 'kauth_v2',
  kauth_v3 = 'kauth_v3',
  konnect = 'konnect',
  konnect_v2 = 'konnect_v2',
  servicehub = 'servicehub',
  kadmin = 'kadmin'
}

/**
 * Enum of available protocols
 */
export enum Protocol {
  rest = 'rest',
  grpc = 'grpc',
}

/**
 * Enum of available environments
 */
export const Environment = Object.freeze({
  gateway: {
    admin: 'admin',
    adminSec: 'adminSec',
    proxy: 'proxy',
    proxy2: 'proxy2',
    proxySec: 'proxySec',
    ec2host: 'ec2host',
    hostName: 'hostName',
    wsProxy: 'wsProxy',
    wssProxy: 'wssProxy',
    keycloak: 'keycloak',
    keycloakSec: 'keycloakSec',
    ec2TestServer: 'ec2TestServer',
  },
  koko: {
    dev: 'dev',
    prod: 'prod',
  },
  kauth: {
    local: 'local',
    dev: 'dev',
    prod: 'prod',
  },
  konnect: {
    local: 'local',
    dev: 'dev',
    prod: 'prod',
  },
  konnect_v2: {
    dev: 'dev',
    prod: 'prod',
  },
  servicehub: {
    dev: 'dev',
    prod: 'prod',
  },
  kadmin: {
    dev: 'dev',
    prod: 'prod',
  },
});

/**
 * Object of available base paths
 */
const getPaths = (geo = getApiGeo()) => {
  return {
    gateway: {
      admin: `http://${getGatewayHost()}:8001`,
      adminSec: `https://${getGatewayHost()}:8444`,
      proxy: `http://${getGatewayHost()}:8000`,
      proxySec: `https://${getGatewayHost()}:8443`,
      proxy2: `http://${getGatewayHost()}:8010`,
      proxySec2: `https://${getGatewayHost()}:8453`,
      wsProxy: `ws://${getGatewayHost()}:8000`,
      wssProxy: `wss://${getGatewayHost()}:8443`,
      keycloak: `http://${getGatewayHost()}:8080`,
      keycloakSec: `https://${getGatewayHost()}:8543`,
      ec2host: 'ec2-18-117-8-125.us-east-2.compue.amazonaws.com',
      ec2TestServer: '18.117.9.215',
      hostName: getGatewayHost(),
    },
    koko: {
      dev: `https://${geo}.api.konghq.tech/konnect-api/api/runtime_groups/${getRuntimeGroupId()}`,
      prod: `https://${geo}.api.konghq.com/konnect-api/api/runtime_groups/${getRuntimeGroupId()}`,
    },
    kauth: {
      dev: 'https://global.api.konghq.tech/kauth',
      prod: 'https://global.api.konghq.com/kauth',
      dev_preview: 'https://global.api.konghq.tech/kauth-preview',
      prod_preview: 'https://global.api.konghq.com/kauth-preview',
    },
    kauth_v2: {
      dev: 'https://global.api.konghq.tech/v2',
      prod: 'https://global.api.konghq.com/v2',
      dev_preview: 'https://global.api.konghq.tech/kauth-preview/v2',
      prod_preview: 'https://global.api.konghq.com/kauth-preview/v2',
    },
    kauth_v3: {
      dev: 'https://global.api.konghq.tech/v3',
      prod: 'https://global.api.konghq.com/v3',
      dev_preview: 'https://global.api.konghq.tech/kauth-preview/v3',
      prod_preview: 'https://global.api.konghq.com/kauth-preview/v3',
    },
    konnect: {
      dev: `https://${geo}.api.konghq.tech/konnect-api`,
      prod: `https://${geo}.api.konghq.com/konnect-api`,
    },
    konnect_v2: {
      dev: `https://${geo}.api.konghq.tech/v2`,
      prod: `https://${geo}.api.konghq.com/v2`,
    },
    servicehub: {
      dev: `https://${geo}.api.konghq.tech/servicehub/v1`,
      prod: `https://${geo}.api.konghq.com/servicehub/v1`,
    },
    kadmin: {
      dev: `https://${geo}.kadmin.admin.konghq.tech`,
      prod: `https://${geo}.kadmin.admin.konghq.com`,
    },
  };
};

/**
 * Get the current app under test (if configured)
 * @param {string | undefined} app current app to check for
 * @returns {string} current app
 */
export const getApp = (app: string | undefined = process.env.TEST_APP): string => {
  if (!app || !(app in App)) {
    throw new Error(
      `App '${app}' does not exist or was not provided. Use 'export TEST_APP=<koko|gateway>'`
    );
  }
  return app;
};

/**
 * Get the current primary protocol under test (if supported)
 * @returns {string} current primary protocol
 */
export const getProtocol = (): string => {
  let protocol = process.env.TEST_PROTOCOL || '';
  if (!protocol) {
    protocol = Protocol.rest;
  }
  if (!(protocol in Protocol)) {
    throw new Error(`Protocol '${protocol}' is not currently supported`);
  }
  return protocol;
};

/**
 * Get the current app environment (if configured)
 * @param {string | undefined} app current app to use
 * @param {string | undefined} environment current environment to check for
 * @returns {string} app environment
 */
export const getEnvironment = (
  app: string | undefined = getApp(),
  environment: string | undefined = process.env.TEST_ENV
): string => {
  if (
    !environment ||
    !(app in Environment) ||
    !(environment in Environment[app])
  ) {
    throw new Error(
      `Environment '${environment}' does not exist or was not provided. Use 'export TEST_ENV=<environment>'`
    );
  }
  return environment;
};

/**
 * Get the base path for the current environment of app under test
 * @param {string | undefined} options.app current app
 * @param {string | undefined} options.environment current environment
 */
export const getBasePath = (
  options: { app?: string | undefined; environment?: string | undefined } = {}
): string => {
  const app = getApp(options.app);
  const environment = getEnvironment(app, options.environment);
  return getPaths()[app][environment];
};

/**
 * Get the base path for a certain endpoint in the gateway test envronment
 */

export const getGatewayBasePath = (key: string): string =>
    getPaths()['gateway'][key];

/**
 * Check if the current test run environment is CI
 * @returns {boolean}- true or false
 */
export const isCI = (): boolean => {
  return process.env.CI === 'true' ? true : false;
};

/**
 * Check if the current app environment matches the target
 * @param {string} environment target to match
 * @returns {boolean} if matched - true; else - false
 */
export const isEnvironment = (environment: string): boolean => {
  return getEnvironment() === environment;
};

/**
 * Check if the current app environment is localhost
 * @param {string} app current app to use
 * @returns {boolean} if localhost - true; else - false
 */
export const isLocal = (app: string = getApp()): boolean => {
  return isEnvironment(Environment[app].local);
};

/**
 * Check if the current app is Gateway
 * @returns {boolean} if Gateway - true; else - false
 */
export const isGateway = (): boolean => {
  return getApp() === App.gateway;
};

/**
 * Check if the current app is Koko
 * @returns {boolean} if Koko - true; else - false
 */
export const isKoko = (): boolean => {
  return getApp() === App.koko;
};

/**
 * Check if the current app is KAuth
 * @returns {boolean} if KAuth - true; else - false
 */
export const isKAuth = (): boolean => {
  return getApp() === App.kauth;
};

/**
 * Check if the current app is KAuth v2
 * @returns {boolean} if KAuth v2 - true; else - false
 */
export const isKAuthV2 = (): boolean => {
  return getApp() === App.kauth_v2;
};

/**
 * Check if the current app is KAuth v3
 * @returns {boolean} if KAuth v3 - true; else - false
 */
export const isKAuthV3 = (): boolean => {
  return getApp() === App.kauth_v3;
};

/**
 * Use preview endpoints (if configured)
 * @returns {boolean} preview
 */
export const isPreview = (): boolean => {
  return process.env.TEST_PREVIEW === 'true';
};

/**
 * Check if the current protocol is gRPC
 * @returns {boolean} if gRPC - true; else - false
 */
export const isGRPC = (): boolean => {
  return getProtocol() === Protocol.grpc;
};

/**
 * Check if the current protocol is REST
 * @returns {boolean} if REST - true; else - false
 */
export const isREST = (): boolean => {
  return getProtocol() === Protocol.rest;
};
