import { Patcher } from "./Patcher.js";
import { logger, RequestMetadata, HeartbeatMetrics } from "./LoggerWrapper.js";
import { PodInfo, IOwnerReference, IAdmissionReview, InstrumentationCR } from "./RequestDefinition.js";
import { AdmissionReviewValidator } from "./AdmissionReviewValidator.js";
import { InstrumentationCRsCollection } from "./InstrumentationCRsCollection.js";

export class Mutator {
    /**
     * Mutates the incoming AdmissionReview of a deployment to enable auto-attach features on its pods
     * @returns An AdmissionReview k8s object that represents a response from the webhook to the API server. Includes the JsonPatch mutation to the incoming AdmissionReview.
     */
    public static async MutatePodTemplate(admissionReview: IAdmissionReview, crs: InstrumentationCRsCollection, clusterArmId: string, clusterArmRegion: string, operationId: string): Promise<string> {
        // this is what we need to return to k8s API server
        const response = {
            apiVersion: "admission.k8s.io/v1",
            kind: "AdmissionReview",
            response: {
                allowed: true, // we only mutate, not admit, so this should always be true as we never want to block any of the customer's API calls
                patch: undefined, // JsonPatch document describing the mutation
                patchType: "JSONPatch",
                uid: "" // must match the uid of the incoming AdmissionReview
            },
        };

        let requestMetadata = new RequestMetadata(null, crs);

        try {
            const mutator: Mutator = new Mutator(admissionReview);
            logger.info(`Original AdmissionReview: ${JSON.stringify(admissionReview)}`, operationId, requestMetadata);

            response.apiVersion = mutator.AdmissionReview.apiVersion;
            response.response.uid = mutator.AdmissionReview.request.uid;
            response.kind = mutator.AdmissionReview.kind;

            requestMetadata = new RequestMetadata(mutator.AdmissionReview.request.uid, crs);
            
            if(!AdmissionReviewValidator.Validate(mutator.AdmissionReview, operationId, requestMetadata)) {
                throw `Validation of the incoming AdmissionReview failed`;
            }

            const podInfo: PodInfo = await mutator.getPodInfo();
            
            const namespace: string = mutator.AdmissionReview.request.object.metadata.namespace;
            if (!namespace) {
                throw `Could not determine the namespace of the incoming object: ${mutator.AdmissionReview}`;
            }

            // find an appropriate CR that dictates whether and how we should mutate
            const crToUse: string = mutator.pickCR();

            const cr: InstrumentationCR = crs.GetCR(namespace, crToUse);
            if (!cr) {
                // no relevant CR found, do not mutate and return with no modifications
                logger.info(`No governing CR found, will not mutate`, operationId, requestMetadata);
                response.response.patch = Buffer.from(JSON.stringify([])).toString("base64");
            } else {
                const armIdMatches = /^\/subscriptions\/(?<SubscriptionId>[^/]+)\/resourceGroups\/(?<ResourceGroup>[^/]+)\/providers\/(?<Provider>[^/]+)\/(?<ResourceType>[^/]+)\/(?<ResourceName>[^/]+).*$/i.exec(clusterArmId);
                if (!armIdMatches || armIdMatches.length != 6) {
                    throw `ARM ID is in a wrong format: ${clusterArmId}`;
                }

                const clusterName = armIdMatches[5];

                logger.info(`Governing CR for the object to be processed (namespace: ${namespace}, deploymentName: ${podInfo.ownerName}): ${JSON.stringify(cr)}`, operationId, requestMetadata);

                const patchData: object[] = await Patcher.PatchPod(
                    mutator.AdmissionReview,
                    podInfo as PodInfo,
                    cr.spec.settings.autoInstrumentationPlatforms,
                    cr.spec.destination.applicationInsightsConnectionString,
                    clusterArmId,
                    clusterArmRegion,
                    clusterName);

                response.response.patch = Buffer.from(JSON.stringify(patchData)).toString("base64");

                logger.addHeartbeatMetric(HeartbeatMetrics.AdmissionReviewActionableCount, 1);
            }

            const result = JSON.stringify(response);
            logger.info(`Determined final response ${mutator.uid}, ${result}`, operationId, requestMetadata);
        
            return result;
        } catch (e) {
            logger.addHeartbeatMetric(HeartbeatMetrics.AdmissionReviewActionableFailedCount, 1);
        
            logger.error(`Exception encountered: ${e}`, operationId, requestMetadata);
            
            response.response.patch = undefined;
            return JSON.stringify(response);
        }
    }

    public readonly AdmissionReview: IAdmissionReview;

    private constructor(message: IAdmissionReview) {
        if(!message) {
            throw `Admission review can't be null`;
        }

        this.AdmissionReview = message;
    }

    public get uid() {
        if (this.AdmissionReview && this.AdmissionReview.request && this.AdmissionReview.request.uid) {
            return this.AdmissionReview.request.uid;
        }
        return "";
    }

    private async getPodInfo(): Promise<PodInfo> {
        const podInfo: PodInfo = new PodInfo();

        podInfo.namespace = this.AdmissionReview.request.namespace;
        podInfo.onlyContainerName = this.AdmissionReview.request.object.spec.template.spec.containers?.length == 1 ? this.AdmissionReview.request.object.spec.template.spec.containers[0].name : null;
        podInfo.ownerKind = this.AdmissionReview.request.object.kind;
        podInfo.ownerName = this.AdmissionReview.request.object.metadata.name;
        podInfo.ownerUid = this.AdmissionReview.request.object.metadata.uid;
                
        return Promise.resolve(podInfo);
    }

    private pickCR(): string {
        const injectDotNetAnnotation: string = this.AdmissionReview.request.object.spec.template.metadata?.annotations?.["instrumentation.opentelemetry.io/inject-dotnet"];
        const injectJavaAnnotation: string = this.AdmissionReview.request.object.spec.template.metadata?.annotations?.["instrumentation.opentelemetry.io/inject-java"];
        const injectNodeJsAnnotation: string = this.AdmissionReview.request.object.spec.template.metadata?.annotations?.["instrumentation.opentelemetry.io/inject-nodejs"];

        const injectAnnotationValues: string[] = [injectDotNetAnnotation, injectJavaAnnotation, injectNodeJsAnnotation];

        // if any of the annotations contain a value other than "true" or "false", that must be the same value for all annotations, we can't apply multiple CRs to the same pod
        const specificCRNames: string[] = injectAnnotationValues.filter(value => value && value.toLocaleLowerCase() != "true" && value.toLocaleLowerCase() != "false", this);
        if(specificCRNames.length > 0 && specificCRNames.filter(value => value?.toLowerCase() === specificCRNames[0].toLowerCase(), this).length != specificCRNames.length) {
            throw `Multiple specific CR names specified in instrumentation.opentelemetry.io/inject-* annotations, that is not supported.`;
        }

        // use CR provided in the annotation(s), otherwise use "default"
        const crToUse: string = specificCRNames.length > 0 ? specificCRNames[0] : "default";
        return crToUse;
    }
}
