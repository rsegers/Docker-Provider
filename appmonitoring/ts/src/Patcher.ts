import { Mutations } from "./Mutations.js";
import { PodInfo, IAdmissionReview, IObjectType, IMetadata, IContainer, ISpec, IVolume, IEnvironmentVariable, AutoInstrumentationPlatforms, IAnnotations } from "./RequestDefinition.js";

export class Patcher {
    /**
     * Calculates a JsonPatch string describing the difference between the old (incoming) and new (outgoing) deployments
    */
    public static async PatchDeployment(admissionReview: IAdmissionReview, crName: string, platforms: AutoInstrumentationPlatforms[]): Promise<object[]> {
        // create a deep copy of the original (incoming) object to be used for making changes
        // strictly speaking, it's not necessary as we could have made changes to the incoming object, but it's more robust to keep it separate and unchanged
        const modifiedDeployment: IObjectType = JSON.parse(JSON.stringify(admissionReview.request.object)) as IObjectType;
        if(!modifiedDeployment) {
            throw `Unable to parse request.object in AdmissionReview: ${admissionReview}`;
        }
        
        // add or modify the annotation
        modifiedDeployment.metadata = modifiedDeployment.metadata ?? <IMetadata>{};
        modifiedDeployment.metadata.annotations = modifiedDeployment.metadata.annotations ?? <IAnnotations>{};
        modifiedDeployment.metadata.annotations["monitor.azure.com/instrumentation-cr"] = crName ?? undefined;
        modifiedDeployment.metadata.annotations["monitor.azure.com/instrumentation-platforms"] = platforms?.length > 0 ? platforms.join(",") : undefined;
      
        // JsonPatch instructing the caller to replace the /spec/template/spec section with the mutated one
        const jsonPatch = [
            {
                op: "replace",
                path: "/metadata/annotations",
                value: modifiedDeployment.metadata.annotations
            }];
        
        return jsonPatch;
    }

    /**
     * Calculates a JsonPatch string describing the difference between the old (incoming) and new (outgoing) pod specs
    */
    public static async PatchReplicaSet(admissionReview: IAdmissionReview, podInfo: PodInfo, platforms: AutoInstrumentationPlatforms[], connectionString: string, armId: string, armRegion: string, clusterName: string): Promise<object[]> {
        // create a deep copy of the original (incoming) object to be used for making changes
        // strictly speaking, it's not necessary as we could have made changes to the incoming object, but it's more robust to keep it separate and unchanged
        const modifiedPodSpec: ISpec = JSON.parse(JSON.stringify(admissionReview.request.object.spec.template.spec)) as ISpec;
        if(!modifiedPodSpec) {
            throw `Unable to parse request.object.spec in AdmissionReview: ${admissionReview}`;
        }

        // add new volumes (used to store agent binaries)
        const newVolumes: IVolume[] = Mutations.GenerateVolumes(platforms);
        modifiedPodSpec.volumes = (modifiedPodSpec.volumes ?? <IVolume[]>[]).concat(newVolumes);
        
        // add new initcontainers (used to copy agent binaries over to the pod)
        const newInitContainers: IContainer[] = Mutations.GenerateInitContainers(platforms);
        modifiedPodSpec.initContainers = (modifiedPodSpec.initContainers ?? <IContainer[]>[]).concat(newInitContainers);
        
        // add new environment variables (used to configure agents)
        const newEnvironmentVariables: object[] = Mutations.GenerateEnvironmentVariables(podInfo, platforms, connectionString, armId, armRegion, clusterName);
        
        modifiedPodSpec.containers?.forEach(container => {
            // hold all environment variables in a dictionary, both existing and new ones
            const allEnvironmentVariables: Record<string, IEnvironmentVariable> = {};

            // add existing environment variables to the dictionary
            (container.env ?? []).forEach(env => allEnvironmentVariables[env.name] = env);
            
            // add new environment variables to the dictionary
            newEnvironmentVariables.forEach(newEnv => {
                const newEnvName: string = (<any>newEnv).name;
                if(!allEnvironmentVariables[newEnvName]) {
                    allEnvironmentVariables[newEnvName] = newEnv as IEnvironmentVariable;
                } else {
                    // duplicate environment variables, need to decide whether to overwrite customer's value or not
                    // for now we are overwriting
                    allEnvironmentVariables[newEnvName] = newEnv as IEnvironmentVariable;
                }
            });

            // set all environment variables contained within the dictionary on the container
            //container.env = <IEnvironmentVariable[]>[];
            for (const envVariableName in allEnvironmentVariables) { 
                container.env.push(allEnvironmentVariables[envVariableName]); 
            }
            
            // add new volume mounts (used by customer's application runtimes to load agent binaries)
            const newVolumeMounts: object[] = Mutations.GenerateVolumeMounts(platforms);
            container.volumeMounts = (container.volumeMounts ?? <IVolume[]>[]).concat(newVolumeMounts);
        });

        // JsonPatch instructing the caller to replace the /spec/template/spec section with the mutated one
        const jsonPatch = [
            {
                op: "replace",
                path: "/spec/template/spec",
                value: modifiedPodSpec
            }];
        
        return jsonPatch;
    }
}
