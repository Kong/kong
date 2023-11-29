import { teams } from '@fixtures';
import {
  getAuthOptions as getAuthOptionsUtil,
  config as configUtil,
  parseKAuthCookies as parseKAuthCookiesUtil,
  setAdminAuthTokens
} from '@kong/kauth-test-utils';
import { AxiosResponseHeaders } from 'axios';

const ACCESS_TOKENS: { [key: string]: string } = {};
const REFRESH_TOKENS: { [key: string]: string } = {};


const getKAuthCookies = (
  teamName: string
): {
  access: string;
  refresh: string;
} => {
  const access = ACCESS_TOKENS[teamName];
  const refresh = REFRESH_TOKENS[teamName];
  if (access == null) {
    throw new Error(`No auth access token found for the team: ${teamName}`);
  }
  if (refresh == null) {
    throw new Error(`No auth refresh token found for the team: ${teamName}`);
  }
  return {
    access,
    refresh,
  };
};

/**
 * Set the KAuth token cookies from the given access/refresh tokens for the target team
 * @param {string} access access token
 * @param {string} refresh refresh token
 * @param {string} teamName organization team name
 * @param {boolean} isPortal option to use portal naming
 */
export const setKAuthCookies = (
  access: string,
  refresh: string,
  teamName: string,
  isPortal = false
) => {
  if (isPortal) {
    access = `${configUtil.constants.PORTAL_ACCESS_TOKEN}=${access}`;
    refresh = `${configUtil.constants.PORTAL_REFRESH_TOKEN}=${refresh}`;
  } else {
    // set admin tokens in utils for functions that use them. TODO -> migration in progress...
    if (teamName === teams.DefaultTeamNames.ORGANIZATION_ADMIN) {
      setAdminAuthTokens(access, refresh);
    }
    access = `${configUtil.constants.KONNECT_ACCESS_TOKEN}=${access}`;
    refresh = `${configUtil.constants.KONNECT_REFRESH_TOKEN}=${refresh}`;
  }
  ACCESS_TOKENS[teamName] = access;
  REFRESH_TOKENS[teamName] = refresh;
};

/**
 * Get the request options with the auth cookie headers set for the target team
 * @param {string} teamName organization team name
 * @returns {any} request auth options
 */
export const getAuthOptions = (
  teamName: string = teams.DefaultTeamNames.ORGANIZATION_ADMIN
): any => {
  const { access, refresh } = getKAuthCookies(teamName);
  return getAuthOptionsUtil(access, refresh);
};


/**
 * Set the KAuth token cookies from the authenticate response headers for the target team
 * @param {AxiosResponseHeaders} responseHeaders authenticate response headers
 * @param {string} teamName organization team name
 * @param {boolean} isPortal option to use portal naming
 * @returns {{ [key: string]: string }} access/refresh token cookies
 */
export const parseKAuthCookies = (
  responseHeaders: AxiosResponseHeaders,
  teamName: string,
  isPortal = false
): {
  access: string;
  refresh: string;
} => {
  const { access, refresh } = parseKAuthCookiesUtil(responseHeaders, isPortal);
  setKAuthCookies(access, refresh, teamName, isPortal);
  return getKAuthCookies(teamName);
};