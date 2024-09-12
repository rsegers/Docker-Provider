import * as k8s from '@kubernetes/client-node';
import { KubeSystemNamespaceName, WebhookName } from './Constants.js'
import { logger, RequestMetadata } from './LoggerWrapper.js';

export class Utilities {
    
    public static async RestartWebhookDeployment(additionalAnnotationNameValue: string[], operationId: string, requestMetadata: RequestMetadata, kc: k8s.KubeConfig, clusterArmId: string, clusterArmRegion: string): Promise<void> {
        let name = null;
        if (!kc) {
            kc = new k8s.KubeConfig();
            kc.loadFromDefault();
        }

        /**
         * The try block contains the logic to restart the webhook deployment. It first gets the webhook deployment by
         * its selector. If there is no deployment or more than one deployment with the selector, it throws an error. If
         * there is exactly one deployment with the selector, it restarts the deployment by updating the annotations with
         * the current time.
         */
        try {
            const k8sApi = kc.makeApiClient(k8s.AppsV1Api);
            const selector = WebhookName;
            const deployments: k8s.V1DeploymentList = (await k8sApi.listNamespacedDeployment(KubeSystemNamespaceName)).body;

            if (!deployments)
            {
                throw new Error(`No Deployments found in ${KubeSystemNamespaceName} namespace!`);
            }
            const matchingDeployments: k8s.V1Deployment[] = deployments.items.filter(deployment => selector.localeCompare(deployment.spec.selector?.matchLabels?.app) === 0);

            if (matchingDeployments.length != 1) {
                throw new Error(`Expected 1 Deployment with selector ${selector}, but found ${matchingDeployments.length}`);
            }

            const deployment: k8s.V1Deployment = matchingDeployments[0];
            const annotations = deployment.spec.template.metadata.annotations ?? {};
            annotations["kubectl.kubernetes.io/restartedAt"] = new Date().toISOString();
            if (additionalAnnotationNameValue) {
                annotations[additionalAnnotationNameValue[0]] = additionalAnnotationNameValue[1];
            }
            deployment.spec.template.metadata.annotations = annotations;

            name = deployment.metadata.name;

            logger.info(`Restarting deployment ${name}...`, operationId, requestMetadata);
            logger.SendEvent("DeploymentRestarting", operationId, null, clusterArmId, clusterArmRegion);
            await k8sApi.replaceNamespacedDeployment(name, KubeSystemNamespaceName, deployment);
            console.log(`Successfully restarted Deployment ${name}`);
            logger.SendEvent("DeploymentRestarted", operationId, null, clusterArmId, clusterArmRegion);
        } catch (err) {
            logger.error(`Failed to restart Deployment ${name}: ${err}`, operationId, requestMetadata);
            logger.SendEvent("DeploymentRestartFailed", operationId, null, clusterArmId, clusterArmRegion, true, err);
            throw err;
        }
    }
}
