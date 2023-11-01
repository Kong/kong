import axios from 'axios';
import * as fs from 'fs';

import {
  Environment,
  expect,
  createGatewayService,
  createRouteForService,
  createConsumer,
  createBasicAuthCredentialForConsumer,
  randomString,
  getBasePath,
  logResponse,
  constructDeckCommand,
  createPlugin,
  execCustomCommand,
  getNegative,
  read_deck_config,
} from '@support';

const adminUrl = `${getBasePath({ environment: Environment.gateway.admin })}`;
const deckFileName = 'kong.json';

describe.skip('decK: Sanity Tests', function () {
  const name = randomString();

  before(async function () {
    /* create some known entities in the gateway */

    const svc = await createGatewayService(name);
    const route = await createRouteForService(svc.id, ['/apitest'], {
      name: name,
    });

    const consumer = await createConsumer(name);
    await createBasicAuthCredentialForConsumer(consumer.username, name);

    await createPlugin({
      name: 'basic-auth',
      service: {
        id: svc.id,
      },
      route: {
        id: route.id,
      },
      config: {
        hide_credentials: true,
      },
    });
  });

  it('should do a ping', async function () {
    const result = execCustomCommand(constructDeckCommand('ping'));
    expect(result.stderr, 'deck ping error').to.be.undefined;
  });

  it('should do a dump', async function () {
    const result = execCustomCommand(
      constructDeckCommand('dump --format json --yes')
    );
    expect(result.stderr, 'deck ping error').to.be.undefined;

    const conf = read_deck_config(deckFileName);

    let service_matched = false;
    let route_matched = false;

    /* check if a known service & route is found */

    expect(
      conf.services && conf.services.length > 0,
      'deck dump does not contain any services'
    ).to.be.true;

    for (const service of conf.services) {
      if (service.name === name) {
        service_matched = true;

        if (service.routes.length) {
          for (const route of service.routes) {
            if (route.name === name) {
              route_matched = true;
              break;
            }
          }
        }
      }
    }

    expect(
      service_matched,
      'deck dump did not contain the expected service'
    ).equals(true);
    expect(
      route_matched,
      'deck dump did not contain the expected route'
    ).equals(true);

    /* check if known consumer is found */

    expect(
      conf.consumers && conf.consumers.length > 0,
      'deck dump does not contain any consumers'
    ).to.be.true;

    let consumer_matched = false;
    let cred_matched = false;

    for (const consumer of conf.consumers) {
      if (consumer.username === name) {
        consumer_matched = true;

        if (consumer.basicauth_credentials.length) {
          for (const basicAuthCred of consumer.basicauth_credentials) {
            if (basicAuthCred.username === name) {
              cred_matched = true;
              break;
            }
          }
        }
      }
    }

    expect(
      consumer_matched,
      'deck dump did not contain the expected consumer'
    ).equals(true);
    expect(
      cred_matched,
      'deck dump did not contain the expected credential'
    ).equals(true);
  });

  it('should reset the db', async function () {
    const result = execCustomCommand(constructDeckCommand('reset --force'));
    expect(result.stderr, 'deck ping error').to.be.undefined;

    /* check if our previously created service is really gone */
    const resp = await getNegative(`${adminUrl}/services/${name}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 404 - no service found').equal(404);
  });

  it('should sync the db', async function () {
    const result = execCustomCommand(
      constructDeckCommand(`sync -s ./${deckFileName}`)
    );
    expect(result.stderr, 'deck ping error').to.be.undefined;

    /* check if our previously created service is really back */
    const resp = await axios(`${adminUrl}/services/${name}`);
    logResponse(resp);

    expect(resp.status, `Service ${name} should exist`).equal(200);
  });

  it('should detect drift', async function () {
    let result = execCustomCommand(
      constructDeckCommand(`diff -s ./${deckFileName} --non-zero-exit-code`)
    );

    expect(result.stderr, 'deck ping error').to.be.undefined;

    /* introduce drift */
    const config = read_deck_config(deckFileName);
    config.services[0].port = 4242;

    fs.writeFileSync(`./${deckFileName}`, JSON.stringify(config));

    result = execCustomCommand(
      constructDeckCommand(`diff -s ./${deckFileName} --non-zero-exit-code`)
    );

    expect(result.stderr, 'deck diff failed').to.be.not.undefined;
    expect(
      result.status,
      'deck diff did not terminate with right exit code'
    ).equals(2);
  });

  after(async function () {
    // after test run use deck reset to remove all of the created entities from kong and remove deck file
    execCustomCommand(constructDeckCommand('reset --force'));

    if (fs.existsSync(`./${deckFileName}`)) {
      execCustomCommand(`rm ./${deckFileName}`);
    }
  });
});
