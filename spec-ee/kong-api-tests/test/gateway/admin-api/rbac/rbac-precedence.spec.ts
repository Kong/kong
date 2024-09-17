import axios from 'axios'
import {
    expect,
    getBasePath,
    isGateway,
    Environment,
    randomString,
    createRole,
    createUser,
    logResponse,
    deleteRole,
    deleteUser,
    createRoleEndpointPermission,
} from '@support'

describe('@smoke @gke: Gateway RBAC: Negative Rule Precedence Check', function () {
    const userName = 'testUser'
    const userToken = randomString()
    const posRoleName = 'positiveRole'
    const negRoleName = 'negativeRole'
    let positiveRole: any
    let negativeRole: any
    let user: any
    let rbacUserUrl: string

    const serviceUrl = `${getBasePath({
        environment: isGateway() ? Environment.gateway.admin : undefined,
    })}/services`

    async function listRolesForUser() {
        const resp = await axios(rbacUserUrl)
        expect(resp.status, 'Status should be 200').to.equal(200)
        return resp
    }

    async function sendReqToServiceUrl(token) {
        return axios({
            url: serviceUrl,
            headers: {
                'Kong-Admin-Token': token
            },
            validateStatus: null
        })
    }

    before(async function () {
        // creating 2 test roles
        const posRoleResp = await createRole(posRoleName)
        positiveRole = {
            name: posRoleResp.name,
            id: posRoleResp.id,
        }

        const negRoleResp = await createRole(negRoleName)
        negativeRole = {
            name: negRoleResp.name,
            id: negRoleResp.id,
        }

        // positive and negative role have opposite permissions
        // negative expected to take precedence
        await createRoleEndpointPermission(positiveRole.id, '/services', 'read,create,update,delete');
        await createRoleEndpointPermission(negativeRole.id, '/services', 'read,create,update,delete', true);

        // create a test user
        const userResp = await createUser(userName, userToken)
        user = {
            name: userResp.name,
            id: userResp.id,
            token: userResp.user_token,
        }

        rbacUserUrl = `${getBasePath({
            environment: isGateway() ? Environment.gateway.admin : undefined,
        })}/rbac/users/${user.id}/roles`
    })

    it('should be able to assign negative role to user', async function () {
        // roles must be assigned one at a time due to parameter restrictions
        const resp = await axios({
            method: 'post',
            url: rbacUserUrl,
            data: {
                roles: negativeRole.name
            },
        })
        expect(resp.status, 'Status should be 201').to.equal(201);
        expect(resp.data.user.name, 'should see correct username').to.equal(userName);
        expect(resp.data.roles, 'should see 1 role for user').to.have.lengthOf(1);
        expect(resp.data.roles[0].name, 'should see correct role').to.equal(negativeRole.name)
    })

    it('should list negative role for user after assignment', async function () {
        const resp = await listRolesForUser()
        expect(resp.data.roles, 'should see 1 role').to.have.lengthOf(1)
        expect(resp.data.roles[0].name, 'should see correct role').to.equal(negativeRole.name)
    })

    it('should not let test user access /services endpoint when assigned negative role', async function () {
        const resp = await sendReqToServiceUrl(userToken)
        logResponse(resp)
        expect(resp.status, 'Status should be 403').to.equal(403)
        expect(resp.data.message, 'should see correct error message').to.equal(`${user.name}, you do not have permissions to read this resource`)
    })

    it('should be able to assign positive role to user', async function () {
        // roles must be assigned one at a time due to parameter restrictions
        const resp = await axios({
            method: 'post',
            url: rbacUserUrl,
            data: {
                roles: positiveRole.name
            },
        })
        expect(resp.status, 'Status should be 201').to.equal(201);
        expect(resp.data.user.name, 'should see correct username').to.equal(userName);
        expect(resp.data.roles, 'should see 2 roles for user').to.have.lengthOf(2);
        expect(await resp.data.roles.map((role: { name: any }) => role.name)).to.include(positiveRole.name, negativeRole.name)
    })

    it('should list both roles for user after assignment', async function () {  
        const resp = await listRolesForUser()
        expect(resp.data.roles, 'should see 2 roles').to.have.lengthOf(2)
        expect(await resp.data.roles.map((role: { name: any }) => role.name)).to.include(positiveRole.name, negativeRole.name)
    })

    it('should let negative permissions take precedence and not allow user to read /services endpoint', async function () {
        const resp = await sendReqToServiceUrl(userToken)

        logResponse(resp)
        expect(resp.status, 'Status should be 403').to.equal(403)
        expect(resp.data.message, 'should see correct error message').to.equal(`${user.name}, you do not have permissions to read this resource`)
    })

    it('should remove negative role from user', async function () {
        const resp = await axios({
            method: 'delete',
            url: rbacUserUrl,
            data: {
                roles: negativeRole.name
            },
            validateStatus: null
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 204').to.equal(204)
    })

    it('should list positive role only for user after removal', async function () {
        const resp = await listRolesForUser()
        expect(resp.data.roles, 'should see 1 role').to.have.lengthOf(1)
        expect(resp.data.roles[0].name, 'should see correct role').to.equal(positiveRole.name)
    })

    it('should allow test user to read /services endpoint after removing negative role', async function () {
        const resp = await sendReqToServiceUrl(userToken)
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)
    })

    after(async function () {
        await deleteRole(posRoleName)
        await deleteRole(negRoleName)
        await deleteUser(userName)
    })
})
