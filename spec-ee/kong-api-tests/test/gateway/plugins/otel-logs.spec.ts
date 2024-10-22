/* eslint-disable no-prototype-builtins */
import axios from 'axios';
import {
  expect,
  Environment,
  getBasePath,
  createGatewayService,
  deleteGatewayService,
  deleteGatewayRoute,
  randomString,
  isGwHybrid,
  wait,
  logResponse,
  deletePlugin,
  createRouteForService,
  resetGatewayContainerEnvVariable,
  getKongContainerName,
  isGateway,
  waitForConfigRebuild,
  createPlugin,
  getTargetFileContent,
  copyFileFromDockerContainer,
  eventually,
  deleteTargetFile,
} from '@support';

describe('@oss: Gateway Plugins: OpenTelemetry Logs', function () {
  const isHybrid = isGwHybrid();
  const gwContainerName = getKongContainerName();
  const otelColContainerName = 'opentelemetry-collector'
  const tracesEndpoint = 'http://opentelemetry-collector:4316/v1/traces';
  const logsEndpoint = 'http://opentelemetry-collector:4316/v1/logs';
  const routePath = '/testOtelLogs'
  const traceIdThatWeArePassing = "0af7651916cd43dd8448eb211c80319c"
  const parentSpanIdThatWeArePassing = "b7ad6b7169203331"
  const fileName = 'file_exporter.json'

  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxy,
  })}`;

  let serviceId: string;
  let routeId: string;
  let pluginId: string;
  let preFunctionPluginId: string;
  let requestId: string;
  let logs: string|any;
  let traces: string|any;

  before(async function () {
    // enable kong otel tracing for requests for this test
    await resetGatewayContainerEnvVariable(
      {
        KONG_TRACING_INSTRUMENTATIONS: 'all',
        KONG_TRACING_SAMPLING_RATE: 1,
        KONG_LOG_LEVEL: 'debug',
      },
      gwContainerName
    );
    if (isHybrid) {
      await resetGatewayContainerEnvVariable(
        {
          KONG_TRACING_INSTRUMENTATIONS: 'all',
          KONG_TRACING_SAMPLING_RATE: 1,
          KONG_LOG_LEVEL: 'debug',
        },
        'kong-dp1'
      );
    }

    //  wait longer if running kong natively
    await wait(gwContainerName === 'kong-cp' ? 2000 : 5000); // eslint-disable-line no-restricted-syntax
    const service = await createGatewayService(randomString());
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [routePath]);
    routeId = route.id;

    const preFunctionReq = await createPlugin({name: 'pre-function', route: {id: routeId}, config: {"access": [
					"kong.log.info(\"this is api test info log\")",
					"kong.log.err(\"this is api test error log\")"
				]}
      })
    
    preFunctionPluginId = preFunctionReq.id
  });

  it('should create otel plugin with logs endpoint', async function () {
    const pluginPayload = {
      name: 'opentelemetry',
      route: {
        id: routeId,
      },
      config: {
        traces_endpoint: tracesEndpoint,
        logs_endpoint: logsEndpoint
      },
    };

    const resp = await axios({
      method: 'post',
      url,
      data: pluginPayload,
    });
    logResponse(resp);

    pluginId = resp.data.id;
    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.config.traces_endpoint, 'Should have correct traces_endpoint').to.equal(tracesEndpoint);
    expect(resp.data.config.logs_endpoint, 'Should have correct logs_endpoint').to.equal(logsEndpoint);

    await waitForConfigRebuild()
  });

  it('should proxy a request with pre-function and otel plugins enabled', async function () {
    const resp = await axios({url: `${proxyUrl}${routePath}`, headers: {traceparent: `00-${traceIdThatWeArePassing }-${parentSpanIdThatWeArePassing}-01`}});
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    requestId = resp.headers['x-kong-request-id']
    console.log("The original request id is:", requestId)
  });

  it('should sanitize the file contents and see matching request.id in the logs with one in the traces', async function () {
    await eventually(async () => {
      copyFileFromDockerContainer(otelColContainerName, fileName)
      // split the file into 2 parts, separate traces and logs
      let contents: any = getTargetFileContent(fileName)
      //  remove dirty special characters coming from otel collector
      contents = contents.replace(/\0+/g, '');
      // split the file contents based on new line, remove empty string from the array, convert string to JSON object
      let allTraces = contents.split('\n').filter(arrayElement => arrayElement).map(arrayElement => JSON.parse(arrayElement))
      // take the last 2 entries (1 resourceLogs and 1 resourceSpans)
      allTraces = allTraces.splice(-2)

      let hasResourceSpans = false;
      let hasResourceLogs = false;
      allTraces.forEach(obj => {
        if (obj.hasOwnProperty('resourceSpans')) {
            hasResourceSpans = true;
            traces = obj
        }
        if (obj.hasOwnProperty('resourceLogs')) {
            hasResourceLogs = true;
            logs = obj
        }
    });
      
      expect(hasResourceSpans && hasResourceLogs, 'Should find both spans and logs in the resources').to.be.true

      // checking that there is matching request.id in the trace spans
      const traceSpans = traces.resourceSpans[0].scopeSpans[0].spans
      let desiredAttribute;
  
      for (const span of traceSpans) {
        if(span.hasOwnProperty('attributes')) {
          for (const attribute of span.attributes) {
            if (attribute.key === 'kong.request.id') {
              desiredAttribute = attribute
              break
            }
          }
        }
      }
    
      expect(desiredAttribute.key, 'Should see the kong.request.id key in the traces').to.eq('kong.request.id')
      expect(desiredAttribute.value.stringValue, 'should see the matching request_id value in the traces').to.eq(requestId)
    });
  });

  it('should see severityNumber, severityText, body, introspection source and line in the logs', async function () {
    let introspectionSource;
    let introspectionLine;

    for(const resourceLog of logs.resourceLogs) {
      for(const scopeLog of resourceLog.scopeLogs) {
        for (const sampleLogRecord of scopeLog.logRecords) {
          expect(sampleLogRecord.timeUnixNano, 'Should have timeUnixNano in the logs').to.be.string
          expect(sampleLogRecord.observedTimeUnixNano, 'Should have observedTimeUnixNano in the logs').to.be.string
          expect(sampleLogRecord.severityNumber, 'Should have severityNumber in the logs').to.be.a('number')
          expect(sampleLogRecord.severityText, 'Should have severityText in the logs').to.be.string
          expect(sampleLogRecord.body, 'Should have body in the logs').to.exist
      
          for (const attribute of sampleLogRecord.attributes) {
            if (attribute.key === 'introspection.source') {
              introspectionSource = attribute
            } else if (attribute.key === 'introspection.current.line') {
              introspectionLine = attribute
            }
          }
      
          expect(introspectionSource.value.stringValue, 'Should see introspection source in the logs').to.be.string
          expect(introspectionLine.value.doubleValue, 'Should see the line of code in the logs').to.be.a('number')
        }
      }
    }
  });

  it('should see flags line in the logs', async function () {
    let isFlagsFound = false

    for(const resourceLog of logs.resourceLogs) {
      for(const scopeLog of resourceLog.scopeLogs) {
        for (const sampleLogRecord of scopeLog.logRecords) {
          if(sampleLogRecord.hasOwnProperty("flags")) {
            isFlagsFound = true
            break
          }
        }
      }
    }

    expect(isFlagsFound, 'Should have flags key in the logs').to.be.true
  });

  it('should see matching request.id in the logs with one in the response header', async function () {
    let desiredAttribute;

    for(const resourceLog of logs.resourceLogs) {
      for(const scopeLog of resourceLog.scopeLogs) {
        for (const logRecord of scopeLog.logRecords) {
          if(logRecord.hasOwnProperty('attributes')) {
            for (const attribute of logRecord.attributes) {
              if (attribute.key === 'request.id') {
                desiredAttribute = attribute
                break
              }
            }
          }
        }
      }
    }

    expect(desiredAttribute.key, 'Should see the request.id key in the logs').to.eq('request.id')
    expect(desiredAttribute.value.stringValue, 'should see the matching request.id value in the logs').to.eq(requestId)
  });

  it('should see the provided trace id in the logs', async function () {
    // always take the last resoureLogs
    const logRecords = logs.resourceLogs[logs.resourceLogs.length - 1].scopeLogs[0].logRecords
    let desiredAttribute;

    for (const logRecord of logRecords) {
      if(logRecord.hasOwnProperty('traceId') && logRecord.traceId !== "") {
        if (logRecord.traceId === traceIdThatWeArePassing) {
          desiredAttribute = logRecord
          break
        }
      }
    }

    expect(desiredAttribute.traceId, 'Should see the correct traceId in the logs').to.eq(traceIdThatWeArePassing)
  });

  it('should see the provided trace id in the traces', async function () {
    const traceSpans = traces.resourceSpans[0].scopeSpans[0].spans
    let desiredAttribute;

    for (const span of traceSpans) {
      if(span.hasOwnProperty('attributes')) {
          if(span.hasOwnProperty('traceId')) {
            if (span.traceId === traceIdThatWeArePassing) {
              desiredAttribute = span
              break
            }
          }
      }
    }
  
    expect(desiredAttribute.traceId, 'Should see matching spanId in the traces').to.eq(traceIdThatWeArePassing)
    expect(desiredAttribute.parentSpanId, 'should see the matching parentSpanId value in the traces').to.eq(parentSpanIdThatWeArePassing)
  });


  it('should see the same log record spanId in the plugin handler traces', async function () {
    let desiredAttribute;
    let targetLogRecord;

    // finding the plugin generated log spanId and traceId to check correlation between the equivalent in traces
    for(const resourceLog of logs.resourceLogs) {
      for(const scopeLog of resourceLog.scopeLogs) {
        for (const logRecord of scopeLog.logRecords) {
          if(logRecord.hasOwnProperty('attributes')) {
            for (const attribute of logRecord.attributes) {
              if (attribute.key === 'introspection.source' && attribute.value.stringValue.includes('kong.log.info')) {
                desiredAttribute = attribute
                targetLogRecord = logRecord
                break
              }
            }
          }
        }
      }
    }

    const logSpanId = targetLogRecord.spanId
    const logTraceId = targetLogRecord.traceId

    expect(desiredAttribute.value.stringValue, 'Should see the target info log in the logs').to.eq(`kong.log.info("this is api test info log")`)
    expect(logSpanId, 'Should have valid spanId for the info log').to.be.string
    expect(logTraceId, 'Should have valid traceId for the info log').to.be.string

    // finding the related trace in the plugin handler traces to see if it has the same spanId, traceId as the log
    let desiredTraceRecord;
    const traceSpans = traces.resourceSpans[0].scopeSpans[0].spans

    for (const span of traceSpans) {
      if (span.name === "kong.access.plugin.pre-function") {
        desiredTraceRecord = span
        break
      }
    }

    expect(desiredTraceRecord.spanId, 'Should have matching spanId in the traces to the generated log').to.eq(logSpanId)
    expect(desiredTraceRecord.traceId, 'Should have matching traceId in the traces to the generated log').to.eq(logTraceId)
  });

  after(async function () {
    await resetGatewayContainerEnvVariable(
      {
        KONG_TRACING_INSTRUMENTATIONS: 'off',
        KONG_TRACING_SAMPLING_RATE: 0.01,
        KONG_LOG_LEVEL: 'info',
      },
      gwContainerName
    );
    if (isHybrid) {
      await resetGatewayContainerEnvVariable(
        {
          KONG_TRACING_INSTRUMENTATIONS: 'off',
          KONG_TRACING_SAMPLING_RATE: 0.01,
          KONG_LOG_LEVEL: 'info',
        },
        'kong-dp1'
      );
    }
  
    deleteTargetFile(fileName)
    await deletePlugin(pluginId);
    await deletePlugin(preFunctionPluginId);
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
  });
});
