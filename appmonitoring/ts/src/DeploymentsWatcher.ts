import { HeartbeatLogs, HeartbeatMetrics, RequestMetadata, logger } from "./LoggerWrapper.js";
import * as k8s from "@kubernetes/client-node";
import { InstrumentationLabelName, DeploymentsListResponse, Deployment } from "./RequestDefinition.js"

export class DeploymentsWatcher {

    private static namePlural = "deployments";
    private static apiGroup = "apps";
    private static apiVersion = "v1";
    
    public static async StartWatching(onNew: (deployment: Deployment, isRemoved: boolean) => void): Promise<void> {
        const kc = new k8s.KubeConfig();
        kc.loadFromDefault();

        const k8sApi = kc.makeApiClient(k8s.AppsV1Api);
        const watch = new k8s.Watch(kc);

        let latestResourceVersion = "0";
        while (true) { // eslint-disable-line
            try {
                latestResourceVersion = await DeploymentsWatcher.Watch(k8sApi, watch, latestResourceVersion, onNew);
            } catch (e) {
                const ex = logger.sanitizeException(e);
                
                logger.addHeartbeatMetric(HeartbeatMetrics.ApiServerCallErrorCount, 1);

                logger.appendHeartbeatLog(HeartbeatLogs.ApiServerTopExceptionsEncountered, JSON.stringify(ex));

                const requestMetadata = new RequestMetadata("Deployment watcher", null);
                logger.error(`K8s deployment watch failure: ${e}`, null, requestMetadata);

                // pause for a bit to avoid generating too much load in case of cascading failures
                await new Promise(r => setTimeout(r, 5000));
            } finally {
                // we ended up here because the watch above either finished gracefully or failed (its lifespan is limited no matter what), so we have to establish a new one
                logger.addHeartbeatMetric(HeartbeatMetrics.ApiServerCallCount, 1);
            }
        }
    }

    private static async Watch(k8sApi: k8s.AppsV1Api, watch: k8s.Watch, latestResourceVersion: string, onNew: (deployment: Deployment, isRemoved: boolean) => void): Promise<string> {
        let requestMetadata = new RequestMetadata("Deployment watcher", null);

        logger.info(`Listing deployments, resourceVersion=${latestResourceVersion}...`, null, requestMetadata);

        const labelSelector = `${InstrumentationLabelName}`;

        const deploymentsResult: DeploymentsListResponse = <DeploymentsListResponse>await k8sApi.listDeploymentForAllNamespaces(
            undefined,
            undefined,
            undefined, // fieldSelector: `metadata.name=name`
            labelSelector, // labelSelector: `labelName=labelValue` or `labelName`
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined);

        logger.info(`Deployments listed, resourceVersion=${deploymentsResult.body.metadata.resourceVersion}`, null, requestMetadata);

        latestResourceVersion = deploymentsResult.body.metadata?.resourceVersion;

        deploymentsResult.body.items.forEach((deployment: Deployment) => { 
            onNew(deployment, false);
        });

        logger.info(`Starting a deployment watch, resourceVersion=${latestResourceVersion}...`, null, requestMetadata);
        
        // watch() doesn't block (it starts the loop and returns immediately), so we can't just return the promise it returns to our caller
        // we must instead create our own promise and resolve it manually when the watch informs us that it stopped via a callback
        const watchIsDonePromise: Promise<string> = new Promise(resolveWatchPromise => {
            watch.watch(`/apis/${DeploymentsWatcher.apiGroup}/${DeploymentsWatcher.apiVersion}/${DeploymentsWatcher.namePlural}`,
                {
                    allowWatchBookmarks: true,
                    resourceVersion: latestResourceVersion,
                    //fieldSelector: 'metadata.name=my-namespace',
                    labelSelector: labelSelector
                },
                (type, apiObj) => {
                    requestMetadata = new RequestMetadata("Deployment watcher", null);

                    try {
                        if (type === "ADDED") {
                            logger.info(`NEW deployment: ${apiObj.metadata?.name} (${apiObj.metadata?.namespace})`, null, requestMetadata);
                            onNew(apiObj, false);
                        } else if (type === "MODIFIED") {
                            logger.info(`MODIFIED deployment: ${apiObj.metadata?.name} (${apiObj.metadata?.namespace})`, null, requestMetadata);
                            onNew(apiObj, false);
                        } else if (type === "DELETED") {
                            logger.info(`DELETED deployment: ${apiObj.metadata?.name} (${apiObj.metadata?.namespace})`, null, requestMetadata);
                            onNew(apiObj, true);
                        } else if (type === "BOOKMARK") {
                            latestResourceVersion = apiObj.metadata?.resourceVersion ?? latestResourceVersion;
                        } else {
                            logger.error(`Unknown object type: ${type}`, null, requestMetadata);
                        }

                        //logger.info(`apiObj: ${JSON.stringify(apiObj)}`, null, requestMetadata);
                    } catch (e) {
                        logger.error(`Failed to process a watched item: ${e}`, null, requestMetadata);
                    }
                },
                err => { // watch is done callback
                    logger.info("Deployments watch has completed", null, requestMetadata);
                    if (err != null) {
                        logger.error(err, null, requestMetadata);
                    }

                    resolveWatchPromise(latestResourceVersion);
                });
        });
        
        return watchIsDonePromise;
    }
}
