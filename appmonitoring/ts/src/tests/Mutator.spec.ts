import { expect, describe, it } from "@jest/globals";
import { Mutator } from "../Mutator.js";
import { IAdmissionReview, IAnnotations, IMetadata, ISpec, InstrumentationCR, AutoInstrumentationPlatforms } from "../RequestDefinition.js";
import { TestObject2, TestObject3, TestObject4, crs, clusterArmId, clusterArmRegion } from "./testConsts.js";
import { logger } from "../LoggerWrapper.js"
import { InstrumentationCRsCollection } from "../InstrumentationCRsCollection.js";

beforeEach(() => {
    logger.setUnitTestMode(true);
});

afterEach(() => {
    jest.restoreAllMocks();
});

describe("Mutator", () => {
    it("Null admission review", async () => {
        const result = JSON.parse(await Mutator.MutatePodTemplate(null, crs, clusterArmId, clusterArmRegion, null));

        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe("");
        expect(result.response.status.code).toBe(400);
        expect(result.response.status.message).toBe("Exception encountered: Admission review can't be null");
    })

    it("Unsupported object kind", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject2));
        admissionReview.request.kind.kind = "Not a pod!";

        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));

        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(400);
        expect(result.response.status.message).toBe("Exception encountered: Validation of the incoming AdmissionReview failed");
    })

    it("Unsupported operation", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject2));
        admissionReview.request.operation = "DELETE";

        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));

        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(400);
        expect(result.response.status.message).toBe("Exception encountered: Validation of the incoming AdmissionReview failed");
    })
    
    it("Valid object2", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject2));
        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));
        
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");
    })

    it("ValidObject3", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject3));
        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));
       
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");
    });

    it("ValidObject4", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject4));
        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));
        
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");
    });

    it("Inject annotations - no annotations", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject4));

        // no annotations
        admissionReview.request.object.spec.template.metadata = <IMetadata> { annotations: null };
        admissionReview.request.object.metadata.namespace = "ns1";

        const crDefault: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "ns1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs]
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=default"
                }
            }
        };

        const cr1: InstrumentationCR = {
            metadata: {
                name: "cr1",
                namespace: "ns1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs]
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=cr1"
                }
            }
        };
        
        const crs: InstrumentationCRsCollection = new InstrumentationCRsCollection();
        crs.Upsert(cr1);       
        crs.Upsert(crDefault);

        // ACT
        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));
        
        // ASSERT
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");

        // confirm default CR was used
        const patchString: string = atob(result.response.patch);
        const resultAR: ISpec = JSON.parse(patchString)[0].value as ISpec;
        expect(resultAR.containers[0].env.find(e => e.name === "APPLICATIONINSIGHTS_CONNECTION_STRING").value).toEqual(crDefault.spec.destination.applicationInsightsConnectionString);
    });

    it("Inject annotations - invalid annotations - multiple CRs", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject4));

        // invalid sets of annotations, all pointing to multiple CRs
        const invalidAnnotationSets: IAnnotations[] = [
            {
                "instrumentation.opentelemetry.io/inject-dotnet": "cr1",
                "instrumentation.opentelemetry.io/inject-java": "cr2"
            },
            {
                "instrumentation.opentelemetry.io/inject-dotnet": "cr1",
                "instrumentation.opentelemetry.io/inject-nodejs": "cr2"
            },
            {
                "instrumentation.opentelemetry.io/inject-java": "cr1",
                "instrumentation.opentelemetry.io/inject-nodejs": "cr2"
            },
            {
                "instrumentation.opentelemetry.io/inject-dotnet": "cr1",
                "instrumentation.opentelemetry.io/inject-java": "cr2",
                "instrumentation.opentelemetry.io/inject-nodejs": "cr3"
            },
            {
                "instrumentation.opentelemetry.io/inject-dotnet": "true",
                "instrumentation.opentelemetry.io/inject-java": "cr2",
                "instrumentation.opentelemetry.io/inject-nodejs": "cr3"
            },
            {
                "instrumentation.opentelemetry.io/inject-dotnet": "cr1",
                "instrumentation.opentelemetry.io/inject-java": "true",
                "instrumentation.opentelemetry.io/inject-nodejs": "cr3"
            },
            {
                "instrumentation.opentelemetry.io/inject-dotnet": "cr1",
                "instrumentation.opentelemetry.io/inject-java": "cr2",
                "instrumentation.opentelemetry.io/inject-nodejs": "true"
            }
        ];
       
        admissionReview.request.object.metadata.namespace = "ns1";

        invalidAnnotationSets.forEach(async annotationSet => {
            const metadata: IMetadata = <IMetadata> { annotations: annotationSet };

            admissionReview.request.object.spec.template.metadata = metadata;

             // ACT
            const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));
            
            // ASSERT
            expect(result.response.allowed).toBe(true);
            expect(result.response.patchType).toBe("JSONPatch");
            expect(result.response.uid).toBe(admissionReview.request.uid);
            expect(result.response.status.code).toBe(400);
            expect(result.response.status.message).toBe("Exception encountered: Multiple specific CR names specified in instrumentation.opentelemetry.io/inject-* annotations, that is not supported.");
        });
    });

    it("Inject annotations - per language configuration with default CR", async () => {
        // ASSUME
        const crDefault: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "ns1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs]
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=default"
                }
            }
        };

        const cr1: InstrumentationCR = {
            metadata: {
                name: "cr1",
                namespace: "ns1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs]
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=cr1"
                }
            }
        };
        
        const crs: InstrumentationCRsCollection = new InstrumentationCRsCollection();
        crs.Upsert(cr1);       
        crs.Upsert(crDefault);

        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject4));

        admissionReview.request.object.metadata.namespace = "ns1";

        const metadata: IMetadata = <IMetadata>{
            annotations: {
                "instrumentation.opentelemetry.io/inject-dotnet": "false",
                "instrumentation.opentelemetry.io/inject-java": "true",
                "instrumentation.opentelemetry.io/inject-nodejs": "true"
            }
        };

        admissionReview.request.object.spec.template.metadata = metadata;

        // ACT
        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));

        // ASSERT
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");
        
        const patchString: string = atob(result.response.patch);
        const resultAR: ISpec = JSON.parse(patchString)[0].value as ISpec;

        expect(resultAR.initContainers.length).toBe(2);
        expect(resultAR.initContainers[0].image).toMatch("/java:");
        expect(resultAR.initContainers[1].image).toMatch("/nodejs:");

        expect(resultAR.containers[0].env.find(e => e.name === "APPLICATIONINSIGHTS_CONNECTION_STRING").value).toEqual(crDefault.spec.destination.applicationInsightsConnectionString);
    });

    it("Inject annotations - per language configuration with specific CR", async () => {
        // ASSUME
        const crDefault: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "ns1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs]
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=default"
                }
            }
        };

        const cr1: InstrumentationCR = {
            metadata: {
                name: "cr1",
                namespace: "ns1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs]
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=cr1"
                }
            }
        };
        
        const crs: InstrumentationCRsCollection = new InstrumentationCRsCollection();
        crs.Upsert(cr1);       
        crs.Upsert(crDefault);

        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject4));

        admissionReview.request.object.metadata.namespace = "ns1";

        const metadata: IMetadata = <IMetadata>{
            annotations: {
                "instrumentation.opentelemetry.io/inject-dotnet": "cr1",
                "instrumentation.opentelemetry.io/inject-java": "false",
                "instrumentation.opentelemetry.io/inject-nodejs": "cr1"
            }
        };

        admissionReview.request.object.spec.template.metadata = metadata;

        // ACT
        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));

        // ASSERT
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");
        
        const patchString: string = atob(result.response.patch);
        const resultAR: ISpec = JSON.parse(patchString)[0].value as ISpec;

        expect(resultAR.initContainers.length).toBe(2);
        expect(resultAR.initContainers[0].image).toMatch("/dotnet:");
        expect(resultAR.initContainers[1].image).toMatch("/nodejs:");

        expect(resultAR.containers[0].env.find(e => e.name === "APPLICATIONINSIGHTS_CONNECTION_STRING").value).toEqual(cr1.spec.destination.applicationInsightsConnectionString);
    });
});