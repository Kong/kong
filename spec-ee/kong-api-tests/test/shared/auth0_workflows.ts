import { teams } from '@fixtures';
import {
  authenticateUser as authenticateUserUtil,
  getUserOrganizations as getUserOrganizationsUtil,
  registerOrganization as registerOrganizationUtil,
} from '@kong/kauth-test-utils';
import {
  expect,
  getAuth0UserCreds,
  getEnvironment,
  randomString,
  setKAuthCookies,
  isKAuthV3,
  App,
  setOrgName,
  setOrgId,
  getOrgId
} from '@support';


export const registerOrganization = async ({
  username = getAuth0UserCreds().username,
  password = getAuth0UserCreds().password,
  orgName = `quality-${randomString()}`,
} = {}) => {
  const orgId = await registerOrganizationUtil(
    username,
    password,
    orgName,
    getEnvironment(),
    getAppVersion()
  );
  setOrgId(orgId);
  setOrgName(orgName);
};

export const getUserOrganizations = async ({
  username = getAuth0UserCreds().username,
  password = getAuth0UserCreds().password,
} = {}) => {
  const orgs = await getUserOrganizationsUtil(
    username,
    password,
    getEnvironment(),
    getAppVersion()
  );
  expect(orgs, 'orgs data array is not empty').to.not.be.empty;
  return orgs;
};

export const authenticateUser = async ({
  username = getAuth0UserCreds().username,
  password = getAuth0UserCreds().password,
  orgId = getOrgId(),
  team = teams.DefaultTeamNames.ORGANIZATION_ADMIN,
} = {}) => {
  const { access, refresh } = await authenticateUserUtil(
    username,
    password,
    orgId,
    getEnvironment(),
    getAppVersion()
  );
  setKAuthCookies(access, refresh, team);
};

const getAppVersion = () => {
  return (isKAuthV3() ? App.kauth_v3 : App.kauth_v2) as string;
};