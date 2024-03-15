import { expect, describe, it } from "@jest/globals";
import { Mutator } from "../Mutator.js";
import { IAdmissionReview, IMetadata, ISpec, InstrumentationCR } from "../RequestDefinition.js";
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
    it("Null", async () => {
        const result: string = await Mutator.MutatePodTemplate(null, crs, clusterArmId, clusterArmRegion, null);
        expect(result).toBe('{"apiVersion":"admission.k8s.io/v1","kind":"AdmissionReview","response":{"allowed":true,"patchType":"JSONPatch","uid":""}}');
    })

    it("Unsupported object", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject2));
        admissionReview.request.kind.kind = "Not a pod!"

        const result: string = await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null);

        expect(result).toEqual(`{"apiVersion":"admission.k8s.io/v1","kind":"${admissionReview.kind}","response":{"allowed":true,"patchType":"JSONPatch","uid":"${admissionReview.request.uid}"}}`);
    })

    it("Unsupported operation", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject2));
        admissionReview.request.operation = "DELETE"

        const result: string = await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null);
        expect(result).toEqual(`{"apiVersion":"admission.k8s.io/v1","kind":"${admissionReview.kind}","response":{"allowed":true,"patchType":"JSONPatch","uid":"${admissionReview.request.uid}"}}`);
    })
    
    it("Valid object 2", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject2));
        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));
        
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
    })

    it("ValidObject3", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject3));
        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));
       
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
    });

    it("ValidObject4", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject4));
        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));
        
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
    });

    it("Inject annotations - no annotations, so use default CR", async () => {
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
                    autoInstrumentationPlatforms: ["DotNet", "Java", "NodeJs"]
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
                    autoInstrumentationPlatforms: ["DotNet", "Java", "NodeJs"]
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=cr1"
                }
            }
        };
        
        const crs: InstrumentationCRsCollection = new InstrumentationCRsCollection();
        crs.Upsert(crDefault);
        crs.Upsert(cr1);       

        // ACT
        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));
        
        // ASSERT
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        
        const patchString: string = atob(result.response.patch);
        const resultAR: ISpec = JSON.parse(patchString)[0].value as ISpec;

        // confirm default CR was used
        expect(resultAR.containers[0].env.find(e => e.name === "APPLICATIONINSIGHTS_CONNECTION_STRING").value).toEqual(crDefault.spec.destination.applicationInsightsConnectionString);
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
                    autoInstrumentationPlatforms: ["DotNet", "Java", "NodeJs"]
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
                    autoInstrumentationPlatforms: ["DotNet", "Java", "NodeJs"]
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=cr1"
                }
            }
        };
        
        const crs: InstrumentationCRsCollection = new InstrumentationCRsCollection();
        crs.Upsert(crDefault);
        crs.Upsert(cr1);       

        // ACT
        const result = JSON.parse(await Mutator.MutatePodTemplate(admissionReview, crs, clusterArmId, clusterArmRegion, null));
        
        // ASSERT
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        
        const patchString: string = atob(result.response.patch);
        const resultAR: ISpec = JSON.parse(patchString)[0].value as ISpec;

        // confirm default CR was used
        expect(resultAR.containers[0].env.find(e => e.name === "APPLICATIONINSIGHTS_CONNECTION_STRING").value).toEqual(crDefault.spec.destination.applicationInsightsConnectionString);
    });
});