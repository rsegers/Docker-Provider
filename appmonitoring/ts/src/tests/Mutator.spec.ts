import { expect, describe, it } from "@jest/globals";
import { Mutator } from "../Mutator.js";
import { IAdmissionReview, IAnnotations, IMetadata, ISpec, InstrumentationCR, AutoInstrumentationPlatforms, IObjectType, DefaultInstrumentationCRName } from "../RequestDefinition.js";
import { TestObject2, TestObject3, TestObject4, crs, clusterArmId, clusterArmRegion, TestReplicaSet1 } from "./testConsts.js";
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
        const result = JSON.parse(await new Mutator(null, crs, clusterArmId, clusterArmRegion, null).Mutate());

        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBeFalsy();
        expect(result.response.status.code).toBe(400);
        expect(result.response.status.message).toBe("Exception encountered: Admission review can't be null");
    });

    it("Unsupported object kind", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject2));
        admissionReview.request.resource.resource = "Not a pod!";

        const result = JSON.parse(await new Mutator(admissionReview, crs, clusterArmId, clusterArmRegion, null).Mutate());

        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(400);
        expect(result.response.status.message).toContain("Exception encountered: Validation of the incoming AdmissionReview failed");
    });

    it("Unsupported operation", async () => {
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject2));
        admissionReview.request.operation = "DELETE";

        const result = JSON.parse(await new Mutator(admissionReview, crs, clusterArmId, clusterArmRegion, null).Mutate());

        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(400);
        expect(result.response.status.message).toContain("Exception encountered: Validation of the incoming AdmissionReview failed");
    });

    it("Mutating deployment - no annotations, default CR found", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject4));

        // no annotations
        admissionReview.request.object.spec.template.metadata = <IMetadata>{ annotations: <IAnnotations>{} };
        admissionReview.request.object.metadata.namespace = "ns1";

        admissionReview.request.object.metadata.annotations = <IAnnotations>{};
        admissionReview.request.object.metadata.annotations.preExistingAnnotationName = "preExistingAnnotationValue";

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
        const result = JSON.parse(await new Mutator(admissionReview, crs, clusterArmId, clusterArmRegion, null).Mutate());

        // ASSERT
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");

        // confirm default CR and its platforms were written into the annotations
        const patchString: string = atob(result.response.patch);
        const annotations: IAnnotations = JSON.parse(patchString)[0].value as IAnnotations;
        expect(annotations.preExistingAnnotationName).toBe("preExistingAnnotationValue");
        expect(annotations["monitor.azure.com/instrumentation-cr"]).toBe(DefaultInstrumentationCRName);
        expect(annotations["monitor.azure.com/instrumentation-platforms"]).toBe("DotNet,Java,NodeJs");
    });

    it("Mutating deployment - no annotations, default CR not found", async () => {
        // ASSUME
        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestObject4));

        // no annotations
        admissionReview.request.object.spec.template.metadata = <IMetadata>{ annotations: <IAnnotations>{} };
        admissionReview.request.object.metadata.namespace = "ns1";

        admissionReview.request.object.metadata.annotations = <IAnnotations>{};
        admissionReview.request.object.metadata.annotations.preExistingAnnotationName = "preExistingAnnotationValue";

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

        // ACT
        const result = JSON.parse(await new Mutator(admissionReview, crs, clusterArmId, clusterArmRegion, null).Mutate());

        // ASSERT
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");

        // confirm both annotations are empty
        const patchString: string = atob(result.response.patch);
        const annotations: IAnnotations = JSON.parse(patchString)[0].value as IAnnotations;
        expect(annotations.preExistingAnnotationName).toBe("preExistingAnnotationValue");
        expect(annotations["monitor.azure.com/instrumentation-cr"]).toBeUndefined();
        expect(annotations["monitor.azure.com/instrumentation-platforms"]).toBeUndefined();
    });

    it("Mutating deployment - invalid annotations - multiple CRs", async () => {
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
            const result = JSON.parse(await new Mutator(admissionReview, crs, clusterArmId, clusterArmRegion, null).Mutate());
            
            // ASSERT
            expect(result.response.allowed).toBe(true);
            expect(result.response.patchType).toBe("JSONPatch");
            expect(result.response.uid).toBe(admissionReview.request.uid);
            expect(result.response.status.code).toBe(400);
            expect(result.response.status.message).toBe("Exception encountered: Multiple specific CR names specified in instrumentation.opentelemetry.io/inject-* annotations, that is not supported.");
        });
    });

    it("Mutating deployment - per language configuration with default CR", async () => {
        // ASSUME
        const crDefault: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "ns1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet, AutoInstrumentationPlatforms.NodeJs]
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
                    autoInstrumentationPlatforms: []
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
        admissionReview.request.object.metadata.annotations = { preExistingAnnotationName: "preExistingAnnotationValue" };

        const metadata: IMetadata = <IMetadata>{
            annotations: {
                "instrumentation.opentelemetry.io/inject-dotnet": "false",
                "instrumentation.opentelemetry.io/inject-java": "true",
                "instrumentation.opentelemetry.io/inject-nodejs": "true"
            }
        };

        admissionReview.request.object.spec.template.metadata = metadata;

        // ACT
        const result = JSON.parse(await new Mutator(admissionReview, crs, clusterArmId, clusterArmRegion, null).Mutate());

        // ASSERT
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");

        // confirm default CR and annotation-enabled platforms were written into the annotations
        const patchString: string = atob(result.response.patch);
        const annotations: IAnnotations = JSON.parse(patchString)[0].value as IAnnotations;
        expect(annotations.preExistingAnnotationName).toBe("preExistingAnnotationValue");
        expect(annotations["monitor.azure.com/instrumentation-cr"]).toBe(DefaultInstrumentationCRName);
        expect(annotations["monitor.azure.com/instrumentation-platforms"]).toBe("Java,NodeJs");
    });

    it("Mutating deployment - per language configuration with specific CR", async () => {
        // ASSUME
        const crDefault: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "ns1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs]
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
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet]
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
        admissionReview.request.object.metadata.annotations = { preExistingAnnotationName: "preExistingAnnotationValue" };

        const metadata: IMetadata = <IMetadata>{
            annotations: {
                "instrumentation.opentelemetry.io/inject-dotnet": "cr1",
                "instrumentation.opentelemetry.io/inject-java": "false",
                "instrumentation.opentelemetry.io/inject-nodejs": "cr1"
            }
        };

        admissionReview.request.object.spec.template.metadata = metadata;

        // ACT
        const result = JSON.parse(await new Mutator(admissionReview, crs, clusterArmId, clusterArmRegion, null).Mutate());

        // ASSERT
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");

        // confirm default CR and annotation-enabled platforms were written into the annotations
        const patchString: string = atob(result.response.patch);
        const annotations: IAnnotations = JSON.parse(patchString)[0].value as IAnnotations;
        expect(annotations.preExistingAnnotationName).toBe("preExistingAnnotationValue");
        expect(annotations["monitor.azure.com/instrumentation-cr"]).toBe(cr1.metadata.name);
        expect(annotations["monitor.azure.com/instrumentation-platforms"]).toBe("DotNet,NodeJs");
    });

    it("Mutating replicaset - no instrumentation-cr annotation", async () => {
        // ASSUME
        const crDefault: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "ns1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs]
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
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet]
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=cr1"
                }
            }
        };
        
        const crs: InstrumentationCRsCollection = new InstrumentationCRsCollection();
        crs.Upsert(cr1);       
        crs.Upsert(crDefault);

        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestReplicaSet1));

        admissionReview.request.object.metadata.namespace = "ns1";
        admissionReview.request.object.metadata.annotations = { 
            preExistingAnnotationName: "preExistingAnnotationValue",

            "monitor.azure.com/instrumentation-platforms": "Java,DotNet" // this shouldn't matter without the instrumentation-cr annotation
        };
        
        // ACT
        const result = JSON.parse(await new Mutator(admissionReview, crs, clusterArmId, clusterArmRegion, null).Mutate());

        // ASSERT
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");

        // confirm that no mutation occured
        const patchString: string = atob(result.response.patch);
        expect((<[]>JSON.parse(patchString)).length).toBe(0);
    });

    it("Mutating replicaset - empty instrumentation-cr annotation", async () => {
        // ASSUME
        const crDefault: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "ns1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs]
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
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet]
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=cr1"
                }
            }
        };
        
        const crs: InstrumentationCRsCollection = new InstrumentationCRsCollection();
        crs.Upsert(cr1);       
        crs.Upsert(crDefault);

        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestReplicaSet1));

        admissionReview.request.object.metadata.namespace = "ns1";
        admissionReview.request.object.metadata.annotations = { 
            preExistingAnnotationName: "preExistingAnnotationValue",

            "monitor.azure.com/instrumentation-cr": "",
            "monitor.azure.com/instrumentation-platforms": "Java,DotNet" // this shouldn't matter since the instrumentation-cr annotation is empty
        };
        
        // ACT
        const result = JSON.parse(await new Mutator(admissionReview, crs, clusterArmId, clusterArmRegion, null).Mutate());

        // ASSERT
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");

        // confirm that no mutation occured
        const patchString: string = atob(result.response.patch);
        expect((<[]>JSON.parse(patchString)).length).toBe(0);
    });

    it("Mutating replicaset - instrumentation-cr annotation points at an existing CR", async () => {
        // ASSUME
        const crDefault: InstrumentationCR = {
            metadata: {
                name: "default",
                namespace: "ns1"
            },
            spec: {
                settings: {
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.Java, AutoInstrumentationPlatforms.NodeJs]
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
                    autoInstrumentationPlatforms: [AutoInstrumentationPlatforms.DotNet]
                },
                destination: {
                    applicationInsightsConnectionString: "InstrumentationKey=cr1"
                }
            }
        };
        
        const crs: InstrumentationCRsCollection = new InstrumentationCRsCollection();
        crs.Upsert(cr1);       
        crs.Upsert(crDefault);

        const admissionReview: IAdmissionReview = JSON.parse(JSON.stringify(TestReplicaSet1));

        admissionReview.request.object.metadata.namespace = "ns1";
        admissionReview.request.object.metadata.annotations = { 
            preExistingAnnotationName: "preExistingAnnotationValue",

            "monitor.azure.com/instrumentation-cr": "cr1",
            "monitor.azure.com/instrumentation-platforms": "DotNet,Java" // this shouldn't matter since the instrumentation-cr annotation is empty
        };
        
        // ACT
        const result = JSON.parse(await new Mutator(admissionReview, crs, clusterArmId, clusterArmRegion, null).Mutate());

        // ASSERT
        expect(result.response.allowed).toBe(true);
        expect(result.response.patchType).toBe("JSONPatch");
        expect(result.response.uid).toBe(admissionReview.request.uid);
        expect(result.response.status.code).toBe(200);
        expect(result.response.status.message).toBe("OK");

        // confirm that mutation correctly occured
        const patchString: string = atob(result.response.patch);
        const resultAR: ISpec = JSON.parse(patchString)[0].value as ISpec;
        expect(resultAR.initContainers.length).toBe(2);
        expect(resultAR.initContainers[0].image).toMatch("/dotnet:");
        expect(resultAR.initContainers[1].image).toMatch("/java:");

        expect(resultAR.containers[0].env.find(e => e.name === "APPLICATIONINSIGHTS_CONNECTION_STRING").value).toEqual(cr1.spec.destination.applicationInsightsConnectionString);
    });
});