import {
  authenticateUser as auth0AuthenticateUser,
  registerOrganization as auth0RegisterOrganization,
} from './auth0_workflows';

export const registerOrgAndAuthenticateAdmin = async () => {
    await auth0RegisterOrganization();
    await auth0AuthenticateUser();
};
