import axios from 'axios';
import { getUrl, expect, logResponse, waitForConfigRebuild } from '@support';
import { authDetails } from '@fixtures';

const url = getUrl('licenses');
const validLicense = authDetails.license.valid;

export const postGatewayEeLicense = async () => {
  const resp = await axios({
    method: 'post',
    url,
    data: {
      payload: validLicense,
    },
  });

  logResponse(resp);
  expect(resp.status, 'Status should be 201').to.equal(201);
  console.log('Gateway EE License was successfully posted');

  // wait until the license is applied
  await waitForConfigRebuild();

  return resp.data;
};

export const deleteGatewayEeLicense = async () => {
  const licenses = await axios(url);
  const licenseId = licenses.data.data[0].id;

  const resp = await axios({
    method: 'delete',
    url: `${url}/${licenseId}`,
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 204').to.equal(204);
};
