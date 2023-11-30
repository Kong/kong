import { teams } from '@fixtures';
import {
  RuntimeGroupsApi,
} from '@kong/khcp-api-client';
import {
  App,
  expect,
  getApiConfig,
  getAuthOptions,
  logResponse,
  setRuntimeGroupId,
  Environment,
  getBasePath,
  getOrgName,
  generatePublicPrivateCertificates,
  getTargetFileContent,
  deployKonnectDataPlane,
  getDataPlaneDockerImage,
  getNegative,
  retryRequest,
  setKonnectControlPlaneId
} from '@support';
import { validate as uuidValidate } from 'uuid';
import axios from 'axios';

const getControlPlanesUrl = (endpoint = 'control-planes') => {
  const basePath = getBasePath({
    app: 'konnect_v2',
    environment: Environment.konnect_v2.dev,
  });

  return `${basePath}/${endpoint}`;
};

export const getDefaultRuntimeGroup = async () => {
  const config = getApiConfig(App.konnect);
  const api = new RuntimeGroupsApi(config);

  const team = teams.DefaultTeamNames.ORGANIZATION_ADMIN;
  const options = getAuthOptions(team);

  const response = await api.getManyBase(
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    options
  );
  logResponse(response);

  expect(response.status, 'response status should be 200').to.equal(200);

  const runtimeGroupId = response.data.data[0].id;
  expect(uuidValidate(runtimeGroupId), 'runtime group id is a UUID').to.be.true;
  setRuntimeGroupId(runtimeGroupId);

  console.info(`\nCurrent Runtime Group id is  >>>   ${runtimeGroupId}  <<<`)
  console.info(`Current Organization name is >>>   ${getOrgName()}    <<<`)
  console.info(`You can access the organization with current user credentials at https://cloud.konghq.tech/us\n`)
};

/**
 * Get control plane and telemetry endpoints to launh a Data Plane
 * @param {object} headers - additional headers to provide with the request
 * @returns {object}
 */
export const getCpAndTelemetryEndpoints = async (headers = {}) => {
  const controlPlanesUrl = getControlPlanesUrl()

  const resp = await axios({
    method: 'get',
    url: controlPlanesUrl,
    headers,
  });
  logResponse(resp)

  expect(resp.status, 'should return status 200').to.equal(200);

  if (resp.data.data.length > 1) {
    throw new Error('There should be only one control plane in the current Organization')
  }

  const controlPlaneEndpoint = resp.data.data[0].config.control_plane_endpoint.split('//')[1]
  const telemetryEndpoint = resp.data.data[0].config.telemetry_endpoint.split('//')[1]
  const controlPlaneId = resp.data.data[0].id

  return { controlPlaneEndpoint, telemetryEndpoint, controlPlaneId }
}

/**
 * Upload the new generated Certificate to Konnect
 * @param {string} controlPlaneId
 * @param {string} publicCertificate - public certificate file content
 * @param {object} headers - optional
 */
export const pinNewDpClientCertificate = async (controlPlaneId: string, publicCertificate: string | undefined, headers?: any) => {
  const url = `${getControlPlanesUrl()}/${controlPlaneId}/dp-client-certificates`

  const resp = await axios({
    method: 'post',
    url,
    data: { "cert": publicCertificate },
    headers,
  });
  logResponse(resp)

  expect(resp.status, 'should return status 201').to.equal(201);
  return resp.data
}

/**
 * Check that Konnect CP and DP have the same config hash
 * @param {string} controlPlaneId
 */
export const checkKonnectCpAndDpConfigHashMatch = async (controlPlaneId) => {
  let dpNodeId = ''

  // Get all DP nodes associated with the Konnect CP
  let req = () => getNegative(`${getControlPlanesUrl()}/${controlPlaneId}/nodes`);
  let assertions = (resp) => {
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.items.length, 'Should see at least one DP node in Konnect').to.be.greaterThanOrEqual(1)
    dpNodeId = resp.data.items[0].id
  };
  await retryRequest(req, assertions);

  // Get the Konnect Control Plane config hash
  const cpConfigHash = await axios(`${getControlPlanesUrl()}/${controlPlaneId}/expected-config-hash`)
  expect(cpConfigHash.status, 'Status should be 200').to.equal(200);
  const expectedConfigHash = cpConfigHash.data.expected_hash

  // Get our target DP node config_hash and check if it is equal to the CP config hash
  req = () => getNegative(`${getControlPlanesUrl()}/${controlPlaneId}/nodes/${dpNodeId}`);
  assertions = (resp) => {
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.item.config_hash, 'Should have matching Konnect and Data Plane config hash').to.eq(expectedConfigHash)
  };
  await retryRequest(req, assertions);
}

export const setupKonnectDataPlane = async () => {
  // GET the required control_plane_endpoint, telemetry_endpoint and control_plane id
  const { controlPlaneEndpoint, telemetryEndpoint, controlPlaneId } = await getCpAndTelemetryEndpoints()
  setKonnectControlPlaneId(controlPlaneId)

  // Generate the keys and the certificate for DP to upload to Konnect
  await generatePublicPrivateCertificates()

  // read the generated file contents to put that in the docker run code snippet
  const certContent = getTargetFileContent('certificate.crt')
  const privateKey = getTargetFileContent('private.pem')

  // Upload the certificate to Konnect
  await pinNewDpClientCertificate(controlPlaneId, certContent)

  // Start the data plane locally
  deployKonnectDataPlane(controlPlaneEndpoint, telemetryEndpoint, certContent, privateKey, getDataPlaneDockerImage())

  // Checking that Konnect CP config expected_hash is the same as the DP config hash
  // This step is required to make sure that the DP is fully set up and is ready to route requests
  await checkKonnectCpAndDpConfigHashMatch(controlPlaneId)
}