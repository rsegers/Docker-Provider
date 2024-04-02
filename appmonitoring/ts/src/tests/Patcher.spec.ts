import { expect, describe, it } from "@jest/globals";
import { Mutations } from "../Mutations.js";
import { IAdmissionReview, PodInfo, IContainer, IVolume, AutoInstrumentationPlatforms, IEnvironmentVariable, IInstrumentationAnnotationValue, InstrumentationCR, ISpec, FluentBitIoExcludeAnnotationName, FluentBitIoExcludeBeforeMutationAnnotationName, IAnnotations } from "../RequestDefinition.js";
import { Patcher } from "../Patcher.js";
import { cr, clusterArmId, clusterArmRegion, clusterName, TestDeployment2 } from "./testConsts.js";
import { logger } from "../LoggerWrapper.js"

beforeEach(() => {
    logger.setUnitTestMode(true);
});

afterEach(() => {
    jest.restoreAllMocks();
});

describe("Patcher", () => {
    it("Patches a deployment correctly", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));

        const cr1: InstrumentationCR = JSON.parse(JSON.stringify(cr));
        const platforms = cr1.spec.settings.autoInstrumentationPlatforms;
        cr1.spec.settings.logCollectionSettings = { disableAppLogs: true };

        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        admissionReview.request.object.metadata.namespace = "ns1";
        admissionReview.request.object.metadata.annotations = { 
            preExistingAnnotationName: "preExistingAnnotationValue"
        };

        const result: object[] = Patcher.PatchSpec(JSON.parse(JSON.stringify(admissionReview.request.object.spec)), cr1, podInfo, platforms, "connection-string", clusterArmId, clusterArmRegion, clusterName);

        expect((<[]>result).length).toBe(2);
        const annotationValue: IInstrumentationAnnotationValue = JSON.parse((<any>result[0]).value) as IInstrumentationAnnotationValue;
        expect(annotationValue.crName).toBe(cr1.metadata.name);
        expect(annotationValue.crResourceVersion).toBe("1");
        expect(annotationValue.platforms).toStrictEqual([AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs]);        

        expect((<any>result[1]).op).toBe("replace");
        expect((<any>result[1]).path).toBe("/spec");
        expect((<any>result[1]).value).not.toBeNull();
        
        const newInitContainers: IContainer[] = Mutations.GenerateInitContainers(platforms);
        expect((<any>result[1]).value.template.spec.initContainers.length).toBe(admissionReview.request.object.spec.template.spec.initContainers.length + newInitContainers.length);
        newInitContainers.forEach(ic => expect((<any>result[1]).value.template.spec.initContainers).toContainEqual(ic));
        admissionReview.request.object.spec.template.spec.initContainers.forEach(ic => expect((<any>result[1]).value.template.spec.initContainers).toContainEqual(ic));

        const newVolumes: IVolume[] = Mutations.GenerateVolumes(platforms);
        expect((<any>result[1]).value.template.spec.volumes.length).toBe(admissionReview.request.object.spec.template.spec.volumes.length + newVolumes.length);
        newVolumes.forEach(vol => expect((<any>result[1]).value.template.spec.volumes).toContainEqual(vol));
        admissionReview.request.object.spec.template.spec.volumes.forEach(vol => expect((<any>result[1]).value.template.spec.volumes).toContainEqual(vol));

        const newEnvironmentVariables: object[] = Mutations.GenerateEnvironmentVariables(podInfo, platforms, true, "connection-string", clusterArmId, clusterArmRegion, clusterName);
        expect((<any>result[1]).value.template.spec.containers.length).toBe(admissionReview.request.object.spec.template.spec.containers.length);
        newEnvironmentVariables.forEach(env => expect((<any>result[1]).value.template.spec.containers[0].env).toContainEqual(env));
        newEnvironmentVariables.forEach(env => expect((<any>result[1]).value.template.spec.containers[1].env).toContainEqual(env));
        admissionReview.request.object.spec.template.spec.containers[0].env.forEach(env => expect((<any>result[1]).value.template.spec.containers[0].env).toContainEqual(env));
        admissionReview.request.object.spec.template.spec.containers[1].env.forEach(env => expect((<any>result[1]).value.template.spec.containers[1].env).toContainEqual(env));

        const newVolumeMounts: object[] = Mutations.GenerateVolumeMounts(platforms);
        expect((<any>result[1]).value.template.spec.containers.length).toBe(admissionReview.request.object.spec.template.spec.containers.length);
        newVolumeMounts.forEach(vm => expect((<any>result[1]).value.template.spec.containers[0].volumeMounts).toContainEqual(vm));
        newVolumeMounts.forEach(vm => expect((<any>result[1]).value.template.spec.containers[1].volumeMounts).toContainEqual(vm));
        admissionReview.request.object.spec.template.spec.containers[0].volumeMounts.forEach(vm => expect((<any>result[1]).value.template.spec.containers[0].volumeMounts).toContainEqual(vm));
        admissionReview.request.object.spec.template.spec.containers[1].volumeMounts.forEach(vm => expect((<any>result[1]).value.template.spec.containers[1].volumeMounts).toContainEqual(vm));
    });

    it("Unpatches a deployment correctly", async () => {
        // ASSUME
        const initialAdmissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        const platforms = cr.spec.settings.autoInstrumentationPlatforms;
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        initialAdmissionReview.request.object.metadata.namespace = "ns1";
        initialAdmissionReview.request.object.metadata.annotations = { 
            preExistingAnnotationName: "preExistingAnnotationValue"
        };

        const mutatedAdmissionReview: IAdmissionReview = JSON.parse(JSON.stringify(initialAdmissionReview));

        const patchResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(mutatedAdmissionReview.request.object.spec, cr, podInfo, platforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ACT
        // unpatch since CR is empty
        const unpatchResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(mutatedAdmissionReview.request.object.spec, null, podInfo, [] as AutoInstrumentationPlatforms[], "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        expect(JSON.stringify(mutatedAdmissionReview)).toBe(JSON.stringify(initialAdmissionReview));

        expect(unpatchResult.length).toBe(3);

        expect((<any>unpatchResult[0]).op).toBe("add");
        expect((<any>unpatchResult[0]).path).toBe("/metadata/annotations/monitor.azure.com~1instrumentation");
        expect((<any>unpatchResult[1]).value).toBeUndefined();

        expect((<any>unpatchResult[1]).op).toBe("remove");
        expect((<any>unpatchResult[1]).path).toBe("/metadata/annotations/monitor.azure.com~1instrumentation");

        expect((<any>unpatchResult[2]).op).toBe("replace");
        expect((<any>unpatchResult[2]).path).toBe("/spec");
        expect(JSON.stringify((<any>unpatchResult[2]).value.template.spec)).toBe(JSON.stringify(initialAdmissionReview.request.object.spec.template.spec));
    });

    it("Does not patch if no CR", async () => {
        // ASSUME
        const initialAdmissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        const platforms = cr.spec.settings.autoInstrumentationPlatforms;
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        initialAdmissionReview.request.object.metadata.namespace = "ns1";
        initialAdmissionReview.request.object.metadata.annotations = { 
            preExistingAnnotationName: "preExistingAnnotationValue"
        };

        const mutatedAdmissionReview: IAdmissionReview = JSON.parse(JSON.stringify(initialAdmissionReview));

        // ACT
        const patchResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(mutatedAdmissionReview.request.object.spec, null, podInfo, platforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        expect(JSON.stringify(mutatedAdmissionReview)).toBe(JSON.stringify(initialAdmissionReview));

        expect(patchResult.length).toBe(3);

        expect((<any>patchResult[0]).op).toBe("add");
        expect((<any>patchResult[0]).path).toBe("/metadata/annotations/monitor.azure.com~1instrumentation");
        expect((<any>patchResult[0]).value).toBeUndefined();

        expect((<any>patchResult[1]).op).toBe("remove");
        expect((<any>patchResult[1]).path).toBe("/metadata/annotations/monitor.azure.com~1instrumentation");
        
        expect((<any>patchResult[2]).op).toBe("replace");
        expect((<any>patchResult[2]).path).toBe("/spec");
        expect(JSON.stringify((<any>patchResult[2]).value.template.spec)).toBe(JSON.stringify(initialAdmissionReview.request.object.spec.template.spec));
    });

    it("Does not patch if autoinstrumentation platform list is empty", async () => {
        // ASSUME
        const initialAdmissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        const platforms = cr.spec.settings.autoInstrumentationPlatforms;
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        initialAdmissionReview.request.object.metadata.namespace = "ns1";
        initialAdmissionReview.request.object.metadata.annotations = { 
            preExistingAnnotationName: "preExistingAnnotationValue"
        };

        const mutatedAdmissionReview: IAdmissionReview = JSON.parse(JSON.stringify(initialAdmissionReview));

        // ACT
        const patchResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(mutatedAdmissionReview.request.object.spec, cr, podInfo, [], "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        // we should still get the name of the governing CR in the annotation, but no mutation must have occured and the platform annotation should be empty
        expect(JSON.stringify(mutatedAdmissionReview)).toBe(JSON.stringify(initialAdmissionReview));

        expect(patchResult.length).toBe(3);

        expect((<any>patchResult[0]).op).toBe("add");
        expect((<any>patchResult[0]).path).toBe("/metadata/annotations/monitor.azure.com~1instrumentation");
        expect((<any>patchResult[0]).value).toBeUndefined();

        expect((<any>patchResult[1]).op).toBe("remove");
        expect((<any>patchResult[1]).path).toBe("/metadata/annotations/monitor.azure.com~1instrumentation");
        
        expect((<any>patchResult[2]).op).toBe("replace");
        expect((<any>patchResult[2]).path).toBe("/spec");
        expect(JSON.stringify((<any>patchResult[2]).value.template.spec)).toBe(JSON.stringify(initialAdmissionReview.request.object.spec.template.spec));
    });

    it("Restores conflicting environment variables during unpatch", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        const platforms = cr.spec.settings.autoInstrumentationPlatforms;
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        admissionReview.request.object.metadata.namespace = cr.metadata.namespace;

        // conflicting environment variable
        admissionReview.request.object.spec.template.spec.containers[0].env = [
            {
                "name": "NODE_NAME",
                "value": "original conflicting value for node name"
            },
            {
                "name": "OTEL_DOTNET_AUTO_LOGS_ENABLED",
                "value": "original conflicting value for dotnet auto logs enabled"
            },
            {
                "name": "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED",
                "value": "original conflicting value for Java logging enabled"
            },
            {
                "name": "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT",
                "value": "original conflicting value for NodeJs configuration content"
            }
        ];

        // ACT
        const patchedResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr, podInfo, platforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));
        const unpatchedResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, null, podInfo, [] as AutoInstrumentationPlatforms[], "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.length).toBe(4);
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME").value).toBe("original conflicting value for node name");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED").value).toBe("original conflicting value for dotnet auto logs enabled");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED").value).toBe("original conflicting value for Java logging enabled");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT").value).toBe("original conflicting value for NodeJs configuration content");
    });

    it("Handles empty environment variable list", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        const platforms = cr.spec.settings.autoInstrumentationPlatforms;
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        admissionReview.request.object.metadata.namespace = cr.metadata.namespace;

        // no environment variables
        admissionReview.request.object.spec.template.spec.containers[0].env = [];

        // ACT
        const patchedResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr, podInfo, platforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));
        const unpatchedResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, null, podInfo, [] as AutoInstrumentationPlatforms[], "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.length).toBeGreaterThan(0);
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.length).toBe(0);
    });

    it("Disables CI logs correctly", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        admissionReview.request.object.spec.template.metadata.annotations["preExistingAnnotation"] = "preExistingAnnotationValue";

        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        const cr1: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "default",
                resourceVersion: "1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs],
                    logCollectionSettings: {
                        disableContainerLogs: true
                    }
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=823201eb-fdbf-468a-bc7b-e685639439b2;IngestionEndpoint=https://uaecentral-0.in.applicationinsights.azure.com/"
                }
            }
        };

        const cr2: InstrumentationCR = JSON.parse(JSON.stringify(cr1));
        cr2.spec.settings.logCollectionSettings.disableContainerLogs = false;

        const cr3: InstrumentationCR = JSON.parse(JSON.stringify(cr1));
        cr3.spec.settings.logCollectionSettings.disableContainerLogs = undefined;

        // ACT
        const result1: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(JSON.parse(JSON.stringify(admissionReview.request.object.spec)), cr1, podInfo, cr1.spec.settings.autoInstrumentationPlatforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));
        const result2: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(JSON.parse(JSON.stringify(admissionReview.request.object.spec)), cr2, podInfo, cr2.spec.settings.autoInstrumentationPlatforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));
        const result3: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(JSON.parse(JSON.stringify(admissionReview.request.object.spec)), cr3, podInfo, cr1.spec.settings.autoInstrumentationPlatforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        const mutatedSpec1 = (<any>result1[1]).value as ISpec;
        const mutatedSpec2 = (<any>result2[1]).value as ISpec;
        const mutatedSpec3 = (<any>result3[1]).value as ISpec;
       
        expect(Object.keys(mutatedSpec1.template.metadata.annotations).length).toBe(2);
        expect(mutatedSpec1.template.metadata.annotations["preExistingAnnotation"]).toBe("preExistingAnnotationValue");
        expect(mutatedSpec1.template.metadata.annotations["fluentbit.io/exclude"]).toBe("true");

        expect(Object.keys(mutatedSpec2.template.metadata.annotations).length).toBe(2);
        expect(mutatedSpec2.template.metadata.annotations["preExistingAnnotation"]).toBe("preExistingAnnotationValue");
        expect(mutatedSpec2.template.metadata.annotations["fluentbit.io/exclude"]).toBe("false");

        expect(Object.keys(mutatedSpec3.template.metadata.annotations).length).toBe(1);
        expect(mutatedSpec3.template.metadata.annotations["preExistingAnnotation"]).toBe("preExistingAnnotationValue");
        expect(mutatedSpec3.template.metadata.annotations["fluentbit.io/exclude"]).toBeUndefined();
    });

    it("Removes CI logs disabling correctly", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        admissionReview.request.object.spec.template.metadata.annotations["preExistingAnnotation"] = "preExistingAnnotationValue";
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        const cr1: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "default",
                resourceVersion: "1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs],
                    logCollectionSettings: {
                        disableContainerLogs: true
                    }
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=823201eb-fdbf-468a-bc7b-e685639439b2;IngestionEndpoint=https://uaecentral-0.in.applicationinsights.azure.com/"
                }
            }
        };

        const cr2: InstrumentationCR = JSON.parse(JSON.stringify(cr1));
        cr2.spec.settings.autoInstrumentationPlatforms = [];

        // ACT
        // patch
        const result1: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr1, podInfo, cr1.spec.settings.autoInstrumentationPlatforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // unpatch
        const result2: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr2, podInfo, cr2.spec.settings.autoInstrumentationPlatforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        const mutatedSpec1 = (<any>result1[1]).value as ISpec;
        const unmutatedSpec2 = (<any>result2[2]).value as ISpec;
       
        expect(mutatedSpec1.template.metadata.annotations["fluentbit.io/exclude"]).toBe("true");
        expect(unmutatedSpec2.template.metadata.annotations["fluentbit.io/exclude"]).toBeUndefined();
    });

    it("Restores CI logs disabling correctly to a preexisting conflicting value when a value is specified in CR", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        admissionReview.request.object.spec.template.metadata.annotations[FluentBitIoExcludeAnnotationName] = "original"

        const cr1: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "default",
                resourceVersion: "1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs],
                    logCollectionSettings: {
                        disableContainerLogs: true
                    }
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=823201eb-fdbf-468a-bc7b-e685639439b2;IngestionEndpoint=https://uaecentral-0.in.applicationinsights.azure.com/"
                }
            }
        };

        const cr2: InstrumentationCR = JSON.parse(JSON.stringify(cr1));
        cr2.spec.settings.autoInstrumentationPlatforms = [];

        // ACT
        // patch
        const result1: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr1, podInfo, cr1.spec.settings.autoInstrumentationPlatforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // unpatch
        const result2: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr2, podInfo, cr2.spec.settings.autoInstrumentationPlatforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        const mutatedSpec1 = (<any>result1[1]).value as ISpec;
        const unmutatedSpec2 = (<any>result2[2]).value as ISpec;
       
        expect(mutatedSpec1.template.metadata.annotations[FluentBitIoExcludeAnnotationName]).toBe("true");
        expect(mutatedSpec1.template.metadata.annotations[FluentBitIoExcludeBeforeMutationAnnotationName]).toBe("original");

        expect(unmutatedSpec2.template.metadata.annotations[FluentBitIoExcludeAnnotationName]).toBe("original");
        expect(unmutatedSpec2.template.metadata.annotations[FluentBitIoExcludeBeforeMutationAnnotationName]).toBeUndefined();
    });

    it("Restores CI logs disabling correctly with preexisting conflicting value when a value is not specified in the CR - option 1", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        admissionReview.request.object.spec.template.metadata.annotations[FluentBitIoExcludeAnnotationName] = "original"

        const cr1: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "default",
                resourceVersion: "1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs],
                    /*logCollectionSettings: {
                        disableContainerLogs: false
                    }*/
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=823201eb-fdbf-468a-bc7b-e685639439b2;IngestionEndpoint=https://uaecentral-0.in.applicationinsights.azure.com/"
                }
            }
        };

        const cr2: InstrumentationCR = JSON.parse(JSON.stringify(cr1));
        cr2.spec.settings.autoInstrumentationPlatforms = [];

        // ACT
        // patch
        const result1: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr1, podInfo, cr1.spec.settings.autoInstrumentationPlatforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // unpatch
        const result2: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr2, podInfo, cr2.spec.settings.autoInstrumentationPlatforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        const mutatedSpec1 = (<any>result1[1]).value as ISpec;
        const unmutatedSpec2 = (<any>result2[2]).value as ISpec;
       
        expect(mutatedSpec1.template.metadata.annotations[FluentBitIoExcludeAnnotationName]).toBe("original");
        expect(mutatedSpec1.template.metadata.annotations[FluentBitIoExcludeBeforeMutationAnnotationName]).toBe("original");

        expect(unmutatedSpec2.template.metadata.annotations[FluentBitIoExcludeAnnotationName]).toBe("original");
        expect(unmutatedSpec2.template.metadata.annotations[FluentBitIoExcludeBeforeMutationAnnotationName]).toBeUndefined();
    });

    it("Restores CI logs disabling correctly with preexisting conflicting value when a value is not specified in the CR - option 2", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        admissionReview.request.object.spec.template.metadata.annotations[FluentBitIoExcludeAnnotationName] = "original"

        const cr1: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "default",
                resourceVersion: "1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs],
                    logCollectionSettings: {
                        // disableContainerLogs: false
                    }
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=823201eb-fdbf-468a-bc7b-e685639439b2;IngestionEndpoint=https://uaecentral-0.in.applicationinsights.azure.com/"
                }
            }
        };

        const cr2: InstrumentationCR = JSON.parse(JSON.stringify(cr1));
        cr2.spec.settings.autoInstrumentationPlatforms = [];

        // ACT
        // patch
        const result1: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr1, podInfo, cr1.spec.settings.autoInstrumentationPlatforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // unpatch
        const result2: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr2, podInfo, cr2.spec.settings.autoInstrumentationPlatforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        const mutatedSpec1 = (<any>result1[1]).value as ISpec;
        const unmutatedSpec2 = (<any>result2[2]).value as ISpec;
       
        expect(mutatedSpec1.template.metadata.annotations[FluentBitIoExcludeAnnotationName]).toBe("original");
        expect(mutatedSpec1.template.metadata.annotations[FluentBitIoExcludeBeforeMutationAnnotationName]).toBe("original");

        expect(unmutatedSpec2.template.metadata.annotations[FluentBitIoExcludeAnnotationName]).toBe("original");
        expect(unmutatedSpec2.template.metadata.annotations[FluentBitIoExcludeBeforeMutationAnnotationName]).toBeUndefined();
    });

    it("Disables app logs correctly", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        const platforms = cr.spec.settings.autoInstrumentationPlatforms;
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        admissionReview.request.object.metadata.namespace = cr.metadata.namespace;

        // conflicting environment variable
        admissionReview.request.object.spec.template.spec.containers[0].env = [
            {
                "name": "NODE_NAME",
                "value": "original conflicting value for node name"
            },
            {
                "name": "OTEL_DOTNET_AUTO_LOGS_ENABLED",
                "value": "original conflicting value for dotnet auto logs enabled"
            },
            {
                "name": "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED",
                "value": "original conflicting value for Java logging enabled"
            },
            // {
            //     "name": "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT",
            //     "value": "original conflicting value for NodeJs configuration content"
            // }
        ];

        // ACT
        const patchedResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr, podInfo, platforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));
        const unpatchedResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, null, podInfo, [] as AutoInstrumentationPlatforms[], "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME").valueFrom.fieldRef.fieldPath).toBe("spec.nodeName");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED").value).toBe("false");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED").value).toBe("false");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT").value).toBe(`{"logInstrumentationOptions":{"console": { "enabled": false }, "bunyan": { "enabled": false },"winston": { "enabled": false }}}`);

        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for node name");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for dotnet auto logs enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for Java logging enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT_BEFORE_AUTO_INSTRUMENTATION")?.value).toBeUndefined();

        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.length).toBe(3);
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME").value).toBe("original conflicting value for node name");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED").value).toBe("original conflicting value for dotnet auto logs enabled");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED").value).toBe("original conflicting value for Java logging enabled");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT")?.value).toBeUndefined();
    });

    it("Handles app logs correctly when logs are enabled in CR", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        const cr1: InstrumentationCR = JSON.parse(JSON.stringify(cr));

        cr1.spec.settings.logCollectionSettings.disableAppLogs = false;

        const platforms = cr.spec.settings.autoInstrumentationPlatforms;
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        admissionReview.request.object.metadata.namespace = cr1.metadata.namespace;

        // conflicting environment variable
        admissionReview.request.object.spec.template.spec.containers[0].env = [
            {
                "name": "NODE_NAME",
                "value": "original conflicting value for node name"
            },
            {
                "name": "OTEL_DOTNET_AUTO_LOGS_ENABLED",
                "value": "original conflicting value for dotnet auto logs enabled"
            },
            {
                "name": "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED",
                "value": "original conflicting value for Java logging enabled"
            },
            {
                "name": "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT",
                "value": "original conflicting value for NodeJs configuration content"
            }
        ];

        // ACT
        const patchedResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr1, podInfo, platforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));
        const unpatchedResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, null, podInfo, [] as AutoInstrumentationPlatforms[], "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME").valueFrom.fieldRef.fieldPath).toBe("spec.nodeName");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED").value).toBe("original conflicting value for dotnet auto logs enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED").value).toBe("original conflicting value for Java logging enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT").value).toBe("original conflicting value for NodeJs configuration content");

        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for node name");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for dotnet auto logs enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for Java logging enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for NodeJs configuration content");

        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.length).toBe(4);
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME").value).toBe("original conflicting value for node name");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED").value).toBe("original conflicting value for dotnet auto logs enabled");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED").value).toBe("original conflicting value for Java logging enabled");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT").value).toBe("original conflicting value for NodeJs configuration content");
    });

    it("Handles app logs correctly when logs settings aren't specified in CR - option 1", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        const cr1: InstrumentationCR = JSON.parse(JSON.stringify(cr));

        cr1.spec.settings.logCollectionSettings = {};

        const platforms = cr.spec.settings.autoInstrumentationPlatforms;
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        admissionReview.request.object.metadata.namespace = cr1.metadata.namespace;

        // conflicting environment variable
        admissionReview.request.object.spec.template.spec.containers[0].env = [
            {
                "name": "NODE_NAME",
                "value": "original conflicting value for node name"
            },
            {
                "name": "OTEL_DOTNET_AUTO_LOGS_ENABLED",
                "value": "original conflicting value for dotnet auto logs enabled"
            },
            {
                "name": "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED",
                "value": "original conflicting value for Java logging enabled"
            },
            // {
            //     "name": "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT",
            //     "value": "original conflicting value for NodeJs configuration content"
            // }
        ];

        // ACT
        const patchedResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr1, podInfo, platforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));
        const unpatchedResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, null, podInfo, [] as AutoInstrumentationPlatforms[], "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME").valueFrom.fieldRef.fieldPath).toBe("spec.nodeName");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED").value).toBe("original conflicting value for dotnet auto logs enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED").value).toBe("original conflicting value for Java logging enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT")?.value).toBeUndefined();

        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for node name");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for dotnet auto logs enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for Java logging enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT_BEFORE_AUTO_INSTRUMENTATION")?.value).toBeUndefined();

        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.length).toBe(3);
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME").value).toBe("original conflicting value for node name");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED").value).toBe("original conflicting value for dotnet auto logs enabled");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED").value).toBe("original conflicting value for Java logging enabled");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT")?.value).toBeUndefined();
    });

    it("Handles app logs correctly when logs settings aren't specified in CR - option 2", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestDeployment2));
        const cr1: InstrumentationCR = JSON.parse(JSON.stringify(cr));

        cr1.spec.settings.logCollectionSettings = undefined;

        const platforms = cr.spec.settings.autoInstrumentationPlatforms;
        const podInfo: PodInfo = <PodInfo>{
            namespace: "default",
            ownerName: "deployment1",
            ownerKind: "Deployment",
            ownerUid: "ownerUid",
            onlyContainerName: "container1"
        };

        admissionReview.request.object.metadata.namespace = cr1.metadata.namespace;

        // conflicting environment variable
        admissionReview.request.object.spec.template.spec.containers[0].env = [
            {
                "name": "NODE_NAME",
                "value": "original conflicting value for node name"
            },
            {
                "name": "OTEL_DOTNET_AUTO_LOGS_ENABLED",
                "value": "original conflicting value for dotnet auto logs enabled"
            },
            {
                "name": "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED",
                "value": "original conflicting value for Java logging enabled"
            },
            // {
            //     "name": "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT",
            //     "value": "original conflicting value for NodeJs configuration content"
            // }
        ];

        // ACT
        const patchedResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, cr1, podInfo, platforms, "connection-string", clusterArmId, clusterArmRegion, clusterName)));
        const unpatchedResult: object[] = JSON.parse(JSON.stringify(Patcher.PatchSpec(admissionReview.request.object.spec, null, podInfo, [] as AutoInstrumentationPlatforms[], "connection-string", clusterArmId, clusterArmRegion, clusterName)));

        // ASSERT
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME").valueFrom.fieldRef.fieldPath).toBe("spec.nodeName");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED").value).toBe("original conflicting value for dotnet auto logs enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED").value).toBe("original conflicting value for Java logging enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT")?.value).toBeUndefined();

        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for node name");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for dotnet auto logs enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED_BEFORE_AUTO_INSTRUMENTATION").value).toBe("original conflicting value for Java logging enabled");
        expect((<any>patchedResult[1]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT_BEFORE_AUTO_INSTRUMENTATION")?.value).toBeUndefined();

        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.length).toBe(3);
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "NODE_NAME").value).toBe("original conflicting value for node name");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "OTEL_DOTNET_AUTO_LOGS_ENABLED").value).toBe("original conflicting value for dotnet auto logs enabled");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_INSTRUMENTATION_LOGGING_ENABLED").value).toBe("original conflicting value for Java logging enabled");
        expect((<any>unpatchedResult[2]).value.template.spec.containers[0].env.find((ev: IEnvironmentVariable) => ev.name === "APPLICATIONINSIGHTS_CONFIGURATION_CONTENT")?.value).toBeUndefined();
    });
});