import * as https from "https";
import { Mutator } from "./Mutator.js";
import { HeartbeatMetrics, HeartbeatLogs, logger, RequestMetadata } from "./LoggerWrapper.js";
import { InstrumentationCR, IAdmissionReview, Deployment, CleanupModeWebhoohEnvironmentVariableName } from "./RequestDefinition.js";
import { InstrumentationCRsWatcher } from "./InstrumentationCRsWatcher.js";
import { InstrumentationCRsCollection } from "./InstrumentationCRsCollection.js"
import fs from "fs";
import { CertificateManager } from "./CertificateManager.js";
import { randomUUID } from 'crypto';
import { DeploymentsWatcher } from "./DeploymentsWatcher.js";
import { DeploymentsCollection } from "./DeploymentsCollection.js";
import { Utilities } from "./Utilities.js";

const containerMode = process.env.CONTAINER_MODE;
const clusterArmId = process.env.ARM_ID;
const clusterArmRegion = process.env.ARM_REGION;
const isServerModeInCleanupMode: boolean = "1".localeCompare(process.env.CLEANUP_MODE) === 0;

let operationId = randomUUID();

if ("secrets-manager".localeCompare(containerMode) === 0) {
    try {
        logger.info("Running in certificate manager mode...", operationId, null);
        logger.SendEvent("CertificateManagerModeRun", operationId, null, clusterArmId, clusterArmRegion);
        logger.addHeartbeatMetric(HeartbeatMetrics.CertificateOperationCount, 1);
        await new CertificateManager().CreateWebhookAndCertificates(operationId, clusterArmId, clusterArmRegion);
        logger.info("Certificate manager mode is done", operationId, null);
        logger.SendEvent("CertificateManagerModeRunSuccess", operationId, null, clusterArmId, clusterArmRegion, true);
    } catch (error) {
        logger.addHeartbeatMetric(HeartbeatMetrics.CertificateOperationFailedCount, 1);
        logger.error(`Certificate manager mode failed: ${JSON.stringify(error)}`, operationId, null);
        logger.SendEvent("CertificateManagerModeRunFailure", operationId, null, clusterArmId, clusterArmRegion, true, error);
        throw error;
    }
    process.exit();
} else if ("secrets-housekeeper".localeCompare(containerMode) === 0) {
    try {
        logger.info("Running in certificate housekeeper mode...", operationId, null);
        await new CertificateManager().ReconcileWebhookAndCertificates(operationId, clusterArmId, clusterArmRegion);
    } catch (error) {
        logger.error(`Failed to Update Certificates, Terminating...\n${JSON.stringify(error)}`, operationId, null);
        logger.SendEvent("SecretsHouseKeeperFailed", operationId, null, clusterArmId, clusterArmRegion, true, error);
        throw error;
    }
    process.exit();
} else if ("cleanup".localeCompare(containerMode) === 0) {
    /* 
      This is the Cleanup mode, we are running as a job in the Helm chart's pre-delete hook, and must do the following:
        - mark the webhook with an annotation that indicates we are in cleanup mode. The webhook will only unmutate once that happens
            - restart the webhook to make it aware of the annotation change
        - get a list of mutated workloads in all namespaces, and keep watching that list until none are left
        - once none are left, successfully return, which will finish the job successfully and unblock Helm chart deletion
        - if we encounter an error during these operations, we must return an error that restarts the job from scratch
    */
    try {
        logger.info("Running in cleanup mode...", operationId, null);

        // mark the webhook deployment with an annotation and restart it
        await Utilities.RestartWebhookDeployment([CleanupModeWebhoohEnvironmentVariableName, "1"], operationId, null, null, clusterArmId, clusterArmRegion);

        const mutatedDeployments: DeploymentsCollection = new DeploymentsCollection();
        await DeploymentsWatcher.StartWatching((deployment: Deployment, isRemoved: boolean) => {
            logger.info(`Deployment: ${deployment.metadata.namespace}/${deployment.metadata.name} was ${isRemoved ? "removed" : "created or modified"}`, operationId, null);

            if(isRemoved) {
                mutatedDeployments.Remove(deployment);

                // if nothing left - our work is done
                if(mutatedDeployments.ListDeployments().length === 0) {
                    logger.info(`Mutated deployment list empty, our work is done`, operationId, null);
                    logger.SendEvent("CleanupSucceeded", operationId, null, clusterArmId, clusterArmRegion, true);

                    process.exit();
                }
            } else {
                mutatedDeployments.Upsert(deployment);
            }
        });
    } catch (error) {
        logger.error(`Failed to perform a cleanup, terminating...\n${JSON.stringify(error)}`, operationId, null);
        logger.SendEvent("CleanupFailed", operationId, null, clusterArmId, clusterArmRegion, true, error);
        throw error;
    }
    process.exit();
}

const crs: InstrumentationCRsCollection = new InstrumentationCRsCollection();

logger.info("Running in server mode...", operationId, null);
logger.SendEvent("ServerModeRun", operationId, null, clusterArmId, clusterArmRegion);

const armIdMatches = /^\/subscriptions\/(?<SubscriptionId>[^/]+)\/resourceGroups\/(?<ResourceGroup>[^/]+)\/providers\/(?<Provider>[^/]+)\/(?<ResourceType>[^/]+)\/(?<ResourceName>[^/]+).*$/i.exec(clusterArmId);
if (!armIdMatches || armIdMatches.length != 6) {
    logger.error(`Cluster ARM ID is in a wrong format: ${clusterArmId}`, operationId, null);
    logger.SendEvent("ArmIdIncorrect", operationId, null, clusterArmId, clusterArmRegion, true);
    throw `Cluster ARM ID is in a wrong format: ${clusterArmId}`;
}

// don't await, this runs an infinite loop in the background
logger.startHeartbeats(operationId);

// don't await, this runs an infinite loop
InstrumentationCRsWatcher.StartWatchingCRs(crs, (cr: InstrumentationCR, isRemoved: boolean) => {
    if (isRemoved) {
        crs.Remove(cr);
    } else {
        crs.Upsert(cr);
    }
    
    const items: InstrumentationCR[] = crs.ListCRs();
    logger.setHeartbeatMetric(HeartbeatMetrics.CRCount, items.length);
    
    const uniqueNamespaces = new Set<string>(items.map(cr => cr.metadata.namespace, this));
    logger.setHeartbeatMetric(HeartbeatMetrics.InstrumentedNamespaceCount, uniqueNamespaces.size);

    let log = "CRs: [";
    for (let i = 0; i < items.length; i++) {
        log += `${items[i].metadata.namespace}/${items[i].metadata.name}, autoInstrumentationPlatforms=${items[i].spec.settings.autoInstrumentationPlatforms}, applicationInsightsConnectionString=${items[i].spec.destination.applicationInsightsConnectionString}}`;
    }

    log += "]"

    logger.info(log, operationId, null);
}, operationId);

let options: https.ServerOptions;
try {
    options = {
        cert: fs.readFileSync("/mnt/webhook/tls.cert"),
        key: fs.readFileSync("/mnt/webhook/tls.key"),
    };

    logger.info(`Certs successfully loaded`, operationId, null);
} catch (e) {
    logger.error(`Failed to load certs: ${e}`, operationId, null);
    logger.SendEvent("CertsLoadFailed", operationId, null, clusterArmId, clusterArmRegion, true, e);
    throw e;
}

const port = process.env.port || 1337;
logger.info(`listening on port ${port}`, operationId, null);

https.createServer(options, (req, res) => {
    logger.info(`Received request with url: ${req.url}, method: ${req.method}, content-type: ${req.headers["content-type"]}`, operationId, null);
    
    logger.addHeartbeatMetric(HeartbeatMetrics.AdmissionReviewCount, 1);

    if (req.method === "POST" && req.headers["content-type"] === "application/json") {
        let body = "";

        req.on("data", (chunk) => {
            body += chunk.toString();
        });

        req.on("end", async () => {
            const begin = Date.now();

            let requestMetadata = new RequestMetadata(null, crs);
            operationId = randomUUID();

            try {
                const admissionReview: IAdmissionReview = JSON.parse(body);

                let uid: string;
                if (admissionReview?.request?.uid) {
                    uid = admissionReview.request.uid;
                    requestMetadata = new RequestMetadata(uid, crs);
                } else {
                    throw `Unable to get request.uid from the incoming admission review`;
                }

                const mutator: Mutator = new Mutator(admissionReview, crs, isServerModeInCleanupMode, clusterArmId, clusterArmRegion, operationId);
                const mutatedObject: string = await mutator.Mutate();

                const end = Date.now();
                
                logger.info(`Done processing request in ${end - begin} ms for ${uid}. ${JSON.stringify(mutatedObject)}`, operationId, requestMetadata);
                
                res.writeHead(200, { "Content-Type": "application/json" });
                res.end(mutatedObject);
            } catch (e) {
                const ex = logger.sanitizeException(e);

                // e must not contain any customer content for privacy reasons, this exception is logged to a Microsoft-owned resource
                logger.appendHeartbeatLog(HeartbeatLogs.AdmissionReviewTopExceptionsEncountered, JSON.stringify(ex));

                logger.error(`Error while processing request: ${JSON.stringify(e)}. Incoming payload: ${body}`, operationId, requestMetadata);
            }
        });
    } else {
        logger.error(`Unacceptable method, returning 404, method: ${req.method}`, operationId, null);
        
        res.writeHead(404);
        res.end();
    }

}).listen(port);

logger.info(`Finished listening on port ${port}, exiting`, null, null);