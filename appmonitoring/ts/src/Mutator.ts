import { Patcher } from "./Patcher.js";
import { logger, RequestMetadata, HeartbeatMetrics } from "./LoggerWrapper.js";
import { PodInfo, IAdmissionReview, InstrumentationCR, AutoInstrumentationPlatforms, DefaultInstrumentationCRName } from "./RequestDefinition.js";
import { AdmissionReviewValidator } from "./AdmissionReviewValidator.js";
import { InstrumentationCRsCollection } from "./InstrumentationCRsCollection.js";
import cluster from "cluster";
import { platform } from "os";

export class Mutator {
    private readonly admissionReview: IAdmissionReview;
    private readonly crs: InstrumentationCRsCollection;
    private readonly clusterArmId: string;
    private readonly clusterArmRegion: string;
    private readonly operationId: string;
    private readonly requestMetadata: RequestMetadata;

    public constructor(admissionReview: IAdmissionReview, crs: InstrumentationCRsCollection, clusterArmId: string, clusterArmRegion: string, operationId: string) {
        this.admissionReview = admissionReview;
        this.crs = crs;
        this.clusterArmId = clusterArmId;
        this.clusterArmRegion = clusterArmRegion;
        this.operationId = operationId;
        this.requestMetadata = new RequestMetadata(this.admissionReview?.request?.uid, this.crs);
    }

    public async Mutate(): Promise<string> {
        const response = this.newResponse();

        try {
            if (!this.admissionReview) {
                throw `Admission review can't be null`;
            }

            if (!AdmissionReviewValidator.Validate(this.admissionReview, this.operationId, this.requestMetadata)) {
                throw `Validation of the incoming AdmissionReview failed: ${JSON.stringify(this.admissionReview)}`;
            } else {
                logger.info(`Validation passed on original AdmissionReview: ${JSON.stringify(this.admissionReview)}`, this.operationId, this.requestMetadata);
            }

            let patch: string;

            switch (this.admissionReview.request.resource?.resource?.toLowerCase()) {
                case "deployments":
                    patch = await this.mutateDeployment();
                    break;

                case "replicasets":
                    patch = await this.mutateReplicaSet();
                    break;

                default:
                    throw `Unsupported resource type in AdmissionReview: ${this.admissionReview.request.resource?.resource}`;
            }

            response.response.patch = patch;
            return JSON.stringify(response);

        } catch (e) {
            const exceptionMessage = `Exception encountered: ${e}`;

            logger.addHeartbeatMetric(HeartbeatMetrics.AdmissionReviewActionableFailedCount, 1);
        
            logger.error(exceptionMessage, this.operationId, this.requestMetadata);
            
            response.response.patch = undefined;
            response.response.status.code = 400;
            response.response.status.message = exceptionMessage;

            return JSON.stringify(response);
        }
    }

    /**
     * Pick a CR that should be used to mutate thid deployment and set its name in an annotation on the deployment
     * That annotation will be propagated to newly created replicasets and will aid in mutating those replicasets
     */
    private async mutateDeployment(): Promise<string> {
        const namespace: string = this.admissionReview.request.object.metadata.namespace;
        if (!namespace) {
            throw `Could not determine the namespace of the incoming object: ${this.admissionReview}`;
        }

        // find an appropriate CR that dictates whether and how we should mutate
        const crNameToUse: string = this.pickCR();

        const cr: InstrumentationCR = this.crs.GetCR(namespace, crNameToUse);

        let platforms: AutoInstrumentationPlatforms[];

        if (!cr) {
            // no relevant CR found, but still need to mutate to ensure annotations are cleared out
            logger.info(`No governing CR found for the deployment (best guess was ${crNameToUse}, but couldn't locate it)`, this.operationId, this.requestMetadata);

            platforms = [];
        } else {
            platforms = this.pickInstrumentationPlatforms(cr);

            logger.info(`Governing CR for the deployment (namespace: ${namespace}, platforms: ${JSON.stringify(platforms)}, deploymentName: ${this.admissionReview.request.object.metadata.name}): ${JSON.stringify(cr)}`, this.operationId, this.requestMetadata);

            logger.addHeartbeatMetric(HeartbeatMetrics.AdmissionReviewActionableCount, 1);
        }

        const patchData: object[] = await Patcher.PatchDeployment(this.admissionReview, cr?.metadata?.name, platforms);
        const patchDataString: string = JSON.stringify(patchData);
        
        logger.info(`Mutated a deployment, returning: ${patchDataString}`, this.operationId, this.requestMetadata);
        
        return Buffer.from(patchDataString).toString("base64");
    }

    /**
     * Mutates the incoming AdmissionReview to enable auto-attach features on its pods
     * @returns An AdmissionReview k8s object that represents a response from the webhook to the API server. Includes the JsonPatch mutation to the incoming AdmissionReview.
     */
    private async mutateReplicaSet(): Promise<string> {
        let patch: string;
        const podInfo: PodInfo = this.getPodInfo();
        
        const namespace: string = this.admissionReview.request.object.metadata.namespace;
        if (!namespace) {
            throw `Could not determine the namespace of the incoming object`;
        }

        // get the name of the governing CR and instrumentation platforms from the annotation (may not be there)
        const crNameToUse: string = this.admissionReview.request.object?.metadata?.annotations?.["monitor.azure.com/instrumentation-cr"];
        const platformNames = this.admissionReview.request.object?.metadata?.annotations?.["monitor.azure.com/instrumentation-platforms"];

        const cr: InstrumentationCR = this.crs.GetCR(namespace, crNameToUse);
        if (!crNameToUse || !cr || podInfo.ownerKind?.toLowerCase() !== "deployment") {
            // no relevant CR found or unsupported replicaset, do not mutate
            logger.info(`No governing CR found (${crNameToUse ? "annotation was " + crNameToUse + ", but couldn't find it" : "no annotation exists"}), or owner kind is wrong (${podInfo.ownerKind}), so will not mutate.`, this.operationId, this.requestMetadata);
            patch = Buffer.from(JSON.stringify([])).toString("base64");
        } else {
            const armIdMatches = /^\/subscriptions\/(?<SubscriptionId>[^/]+)\/resourceGroups\/(?<ResourceGroup>[^/]+)\/providers\/(?<Provider>[^/]+)\/(?<ResourceType>[^/]+)\/(?<ResourceName>[^/]+).*$/i.exec(this.clusterArmId);
            if (!armIdMatches || armIdMatches.length != 6) {
                throw `ARM ID is in a wrong format: ${this.clusterArmId}`;
            }

            const clusterName = armIdMatches[5];

            const platforms: AutoInstrumentationPlatforms[] = [];
            platformNames.split(",").forEach(platformName => platforms.push(AutoInstrumentationPlatforms[platformName]));

            logger.info(`Governing CR for the object to be processed (namespace: ${namespace}, deploymentName: ${podInfo.ownerName}): ${JSON.stringify(cr)} with platforms: ${JSON.stringify(platforms)}`, this.operationId, this.requestMetadata);

            const patchData: object[] = await Patcher.PatchReplicaSet(
                this.admissionReview,
                podInfo as PodInfo,
                platforms,
                cr.spec.destination.applicationInsightsConnectionString,
                this.clusterArmId,
                this.clusterArmRegion,
                clusterName);

            const patchDataString: string = JSON.stringify(patchData);
            logger.info(`Mutated a replicaset, returning: ${patchDataString}`, this.operationId, this.requestMetadata);

            patch = Buffer.from(patchDataString).toString("base64");

            logger.addHeartbeatMetric(HeartbeatMetrics.AdmissionReviewActionableCount, 1);
        }

        return patch;
    }           

    private newResponse() {
        const response = {
            apiVersion: "admission.k8s.io/v1",
            kind: "AdmissionReview",
            response: {
                allowed: true, // we only mutate, not admit, so this should always be true as we never want to block any of the customer's API calls
                patch: undefined, // JsonPatch document describing the mutation
                patchType: "JSONPatch",
                uid: "", // must match the uid of the incoming AdmissionReview,
                status: {
                    code: 200, // indicate the type of success/error to k8s
                    message: "OK"
                }
            },
        };

        response.apiVersion = this.admissionReview?.apiVersion;
        response.response.uid = this.admissionReview?.request?.uid;
        response.kind = this.admissionReview?.kind;

        return response;
    }

    private get uid() {
        if (this.admissionReview && this.admissionReview.request && this.admissionReview.request.uid) {
            return this.admissionReview.request.uid;
        }
        return "";
    }

    private getPodInfo(): PodInfo {
        const podInfo: PodInfo = new PodInfo();

        podInfo.namespace = this.admissionReview.request.object.metadata.namespace;
        podInfo.onlyContainerName = this.admissionReview.request.object.spec.template.spec.containers?.length === 1 ? this.admissionReview.request.object.spec.template.spec.containers[0].name : null;
        podInfo.ownerKind = this.admissionReview.request.object.metadata.ownerReferences[0]?.kind;
        podInfo.ownerName = this.admissionReview.request.object.metadata.ownerReferences[0]?.name;
        podInfo.ownerUid = this.admissionReview.request.object.metadata.ownerReferences[0]?.uid;
                
        return podInfo;
    }

    private pickCR(): string {
        const injectDotNetAnnotation: string = this.admissionReview.request.object.spec.template.metadata?.annotations?.["instrumentation.opentelemetry.io/inject-dotnet"];
        const injectJavaAnnotation: string = this.admissionReview.request.object.spec.template.metadata?.annotations?.["instrumentation.opentelemetry.io/inject-java"];
        const injectNodeJsAnnotation: string = this.admissionReview.request.object.spec.template.metadata?.annotations?.["instrumentation.opentelemetry.io/inject-nodejs"];

        const injectAnnotationValues: string[] = [injectDotNetAnnotation, injectJavaAnnotation, injectNodeJsAnnotation];

        // if any of the annotations contain a value other than "true" or "false", that must be the same value for all annotations, we can't apply multiple CRs to the same pod
        const specificCRNames: string[] = injectAnnotationValues.filter(value => value && value.toLowerCase() != "true" && value.toLowerCase() != "false", this);
        if(specificCRNames.length > 0 && specificCRNames.filter(value => value?.toLowerCase() === specificCRNames[0].toLowerCase(), this).length != specificCRNames.length) {
            throw `Multiple specific CR names specified in instrumentation.opentelemetry.io/inject-* annotations, that is not supported.`;
        }

        // use CR provided in the annotation(s), otherwise use default
        const crToUse: string = specificCRNames.length > 0 ? specificCRNames[0] : DefaultInstrumentationCRName;
        return crToUse;
    }

    private pickInstrumentationPlatforms(cr: InstrumentationCR): AutoInstrumentationPlatforms[] {
        // assuming annotation set is valid (we validated it already when mutating deployment)
        // annotations are on the pod template spec
        const injectDotNetAnnotation: string = this.admissionReview.request.object.spec.template.metadata?.annotations?.["instrumentation.opentelemetry.io/inject-dotnet"];
        const injectJavaAnnotation: string = this.admissionReview.request.object.spec.template.metadata?.annotations?.["instrumentation.opentelemetry.io/inject-java"];
        const injectNodeJsAnnotation: string = this.admissionReview.request.object.spec.template.metadata?.annotations?.["instrumentation.opentelemetry.io/inject-nodejs"];

        const injectAnnotationValues: string[] = [injectDotNetAnnotation, injectJavaAnnotation, injectNodeJsAnnotation];

        if(injectAnnotationValues.filter(value => value).length == 0) {
            // no annotations specified, use platform list from the CR
            // this is only possible for the default CR (it was assumed in the absence of annotations)
            return cr.spec.settings.autoInstrumentationPlatforms;
        }

        const platforms: AutoInstrumentationPlatforms[] = [];

        if (injectDotNetAnnotation && injectDotNetAnnotation.toLowerCase() !== "false") {
            platforms.push(AutoInstrumentationPlatforms.DotNet);
        }

        if (injectJavaAnnotation && injectJavaAnnotation.toLowerCase() !== "false") {
            platforms.push(AutoInstrumentationPlatforms.Java);
        }

        if (injectNodeJsAnnotation && injectNodeJsAnnotation.toLowerCase() !== "false") {
            platforms.push(AutoInstrumentationPlatforms.NodeJs);
        }

        return platforms;
    }
}
