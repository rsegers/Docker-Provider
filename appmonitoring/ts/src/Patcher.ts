import { isNull } from "util";
import { Mutations } from "./Mutations.js";
import { PodInfo, IContainer, ISpec, IVolume, IEnvironmentVariable, AutoInstrumentationPlatforms, IVolumeMount, InstrumentationAnnotationName, InstrumentationCR, IInstrumentationAnnotationValue, FluentBitIoExcludeAnnotationName, IMetadata, IAnnotations, FluentBitIoExcludeBeforeMutationAnnotationName } from "./RequestDefinition.js";

export class Patcher {

    private static readonly EnvironmentVariableBackupSuffix: string = "_BEFORE_AUTO_INSTRUMENTATION";

    private static readonly MutatedMarkerEnvironmentVariableName: string = "AZURE_MONITOR_MUTATION";
    
    /**
     * Calculates a JsonPatch string describing the difference between the old (incoming) and new (outgoing) spec
     * The spec is also patched in-place
    */
    public static PatchSpec(spec: ISpec, cr: InstrumentationCR, podInfo: PodInfo, platforms: AutoInstrumentationPlatforms[], connectionString: string, armId: string, armRegion: string, clusterName: string): object[] {
        if (!spec) {
            throw `Unable to parse request.object.spec in AdmissionReview: ${spec}`;
        }

        // remove all mutation (in case it is already mutated)
        this.Unpatch(spec);

        this.Patch(cr, platforms, spec, podInfo, connectionString, armId, armRegion, clusterName);

        const jsonPatch: object[] = [];
        const annotationName = `/metadata/annotations/${InstrumentationAnnotationName.replace("/", "~1")}`;  // a slash is escaped as ~1 in Json Patch
        if (cr && platforms.length > 0) {
            jsonPatch.push(...[
                // add annotation to the object describing what mutation was applied
                {
                    op: "add", // add will create an element if missing, or overwrite if present
                    path: annotationName,
                    value: JSON.stringify(<IInstrumentationAnnotationValue> {
                        crName: cr.metadata.name,
                        crResourceVersion: cr.metadata.resourceVersion,
                        platforms: <string[]>platforms
                    })
                }
            ]);
        } else {
            // no CR to apply or no instrumentation platforms, we must remove the annotation
            jsonPatch.push(...[
                {
                    op: "add", // add will create an element if missing, or overwrite if present, this is required because remove below will fail if the element doesn't exist
                    path: annotationName,
                    value: undefined
                },
                {
                    op: "remove", // remove will delete the element if it exists, otherwise it will fail, which is why the add above is required
                    path: annotationName
                }
            ]);
        }

        jsonPatch.push(
            // replace the pod spec section with the mutated one
            {
                op: "replace",
                path: "/spec",
                value: spec
            }
        );

        return jsonPatch;
    }

    private static Patch(cr: InstrumentationCR, platforms: AutoInstrumentationPlatforms[], spec: ISpec, podInfo: PodInfo, connectionString: string, armId: string, armRegion: string, clusterName: string) {
        // currently we don't mutate if no auto-instrumentation platforms are used
        // going forward, we'll have to ensure we still do auto-wiring in that case
        if (cr && platforms?.length > 0) {
            const podSpec = spec.template.spec;

            // add new pod annotations to disable CI logs if requested
            spec.template.metadata = spec.template.metadata ?? <IMetadata>{};
            spec.template.metadata.annotations = spec.template.metadata?.annotations ?? <IAnnotations>{};
            if (spec.template.metadata.annotations[FluentBitIoExcludeAnnotationName] != null) {
                // a value is provided and must be saved to be restored during unpatching
                spec.template.metadata.annotations[FluentBitIoExcludeBeforeMutationAnnotationName] = spec.template.metadata.annotations[FluentBitIoExcludeAnnotationName];
            }

            if (cr.spec?.settings?.logCollectionSettings?.disableContainerLogs != null) {
                // we have a setting to use
                spec.template.metadata.annotations[FluentBitIoExcludeAnnotationName] = cr.spec.settings.logCollectionSettings.disableContainerLogs ? "true" : "false";
            }

            // add new volumes (used to store agent binaries)
            const newVolumes: IVolume[] = Mutations.GenerateVolumes(platforms);
            podSpec.volumes = (podSpec.volumes ?? <IVolume[]>[]).concat(newVolumes);

            // add new initcontainers (used to copy agent binaries over to the pod)
            const newInitContainers: IContainer[] = Mutations.GenerateInitContainers(platforms);
            podSpec.initContainers = (podSpec.initContainers ?? <IContainer[]>[]).concat(newInitContainers);

            // add new environment variables (used to configure agents)
            const newEnvironmentVariables: IEnvironmentVariable[] = Mutations.GenerateEnvironmentVariables(podInfo, platforms, connectionString, armId, armRegion, clusterName);

            podSpec.containers?.forEach(container => {
                // hold all environment variables in a dictionary, both existing and new ones
                const allEnvironmentVariables: Record<string, IEnvironmentVariable> = {};

                // add existing environment variables to the dictionary
                container.env?.forEach(env => allEnvironmentVariables[env.name] = env);

                // add new environment variables to the dictionary
                newEnvironmentVariables.forEach(newEnv => {
                    if (!allEnvironmentVariables[newEnv.name]) {
                        // this mutation environment variable is not present in the container originally, so just add it
                        allEnvironmentVariables[newEnv.name] = newEnv;
                    } else {
                        // we are overwriting an environment variable which already exists in the container
                        // save the original value into a backup environment variable
                        const backupName = `${newEnv.name}${Patcher.EnvironmentVariableBackupSuffix}`;
                        const backupEV: IEnvironmentVariable = JSON.parse(JSON.stringify(allEnvironmentVariables[newEnv.name])) as IEnvironmentVariable;
                        backupEV.name = backupName;
                        allEnvironmentVariables[backupName] = backupEV;

                        allEnvironmentVariables[newEnv.name] = newEnv;
                    }
                });

                // set all environment variables contained within the dictionary on the container
                container.env = <IEnvironmentVariable[]>[];
                for (const envVariableName in allEnvironmentVariables) {
                    container.env.push(allEnvironmentVariables[envVariableName]);
                }

                /*
                    We could be receiving customer's original set of environment variables (e.g. in case of kubectl apply),
                    or we could be receiving a mutated version of environment variables (e.g. in case of kubectl rollout restart for an object that is already mutated).
    
                    For each instrumentation-related environment variable we will use a backup environment variable which has name of the format `${envVariableName}${Patcher.EnvironmentVariableBackupSuffix}`
                    and stores the original customer's value (if any). The backup environment variable only exists if there is an original value to store.
    
                    Additionally, during mutation we will add an additional environment variable to indicate that the entire list of environment variables is mutated.
    
                    When reverting mutation, the presence of this additional environment variable will tell us what to do with instrumentation-related environment variables that have no backup environment variable.
                    If the additional environment variable is present - we must remove such environment variable. Otherwise, we must keep it with the present value.
    
                    The reason we are using an additional environment variable to indicate mutation and not an annnotation or a similar mechanism is because
                    depending on a way the change is made there could be discrepancies between environment variable list specifically and other parts of the object (e.g. the customer could remove our custom annotation and reapply YAML)
                */
                if (!container.env.find(ev => ev.name === this.MutatedMarkerEnvironmentVariableName)) {
                    container.env?.push({
                        name: this.MutatedMarkerEnvironmentVariableName,
                        value: ""
                    });
                }

                // add new volume mounts (used by customer's application runtimes to load agent binaries)
                const newVolumeMounts: IVolumeMount[] = Mutations.GenerateVolumeMounts(platforms);
                container.volumeMounts = (container.volumeMounts ?? <IVolumeMount[]>[]).concat(newVolumeMounts);
            });
        }
    }

    /**
     * Removes all mutations from a spec in-place
     */
    private static Unpatch(spec: ISpec): void {
        const podSpec: ISpec = spec?.template?.spec;
        
        if (!spec || !podSpec) {
            throw `Unable to parse spec from AdmissionReview: ${JSON.stringify(spec)}`;
        }

        // remove pod annotations
        const isMutated: boolean = podSpec.containers?.filter(container => container.env?.find(ev => ev.name === this.MutatedMarkerEnvironmentVariableName))?.length > 0;
        if(isMutated) {
            spec.template.metadata = spec.template.metadata ?? <IMetadata>{};
            spec.template.metadata.annotations = spec.template.metadata?.annotations ?? <IAnnotations>{};

            delete spec.template.metadata.annotations[FluentBitIoExcludeAnnotationName];
            if(spec.template.metadata.annotations[FluentBitIoExcludeBeforeMutationAnnotationName] != null) {
                spec.template.metadata.annotations[FluentBitIoExcludeAnnotationName] = spec.template.metadata.annotations[FluentBitIoExcludeBeforeMutationAnnotationName];
                delete spec.template.metadata.annotations[FluentBitIoExcludeBeforeMutationAnnotationName];
            }
        }

        // we are removing all mutations (regardless of whether only some mutations are applied based on the platforms used)
        const allPlatforms: AutoInstrumentationPlatforms[] = [];
        Object.keys(AutoInstrumentationPlatforms).forEach(key => allPlatforms.push(AutoInstrumentationPlatforms[key]));
        
        // remove volumes by name
        const volumesToRemove: IVolume[] = Mutations.GenerateVolumes(allPlatforms);
        podSpec.volumes = podSpec.volumes?.filter(volume => !volumesToRemove.find(vtr => volume.name === vtr.name));
        
        // remove init containers by name
        const initContainersToRemove: IContainer[] = Mutations.GenerateInitContainers(allPlatforms);
        podSpec.initContainers = podSpec.initContainers?.filter(ic => !initContainersToRemove.find(ictr => ic.name === ictr.name));

        // remove environment variables and volume mounts from all containers by name
        // we don't care about values of environment variables here, we just need all names
        const environmentVariablesToRemove: IEnvironmentVariable[] = Mutations.GenerateEnvironmentVariables(new PodInfo(), allPlatforms, "", "", "", "");
        const volumeMountsToRemove: IVolumeMount[] = Mutations.GenerateVolumeMounts(allPlatforms);

        podSpec.containers?.forEach(container => {
            environmentVariablesToRemove.forEach(evtr => {
                // find the environment variable in the container
                const evIndex = container.env?.findIndex(ev => ev.name === evtr.name);

                if(evIndex === -1) {
                    // container doesn't have this environment variable, continue
                    return;
                }

                // container contains this environment variable

                // is there a backup environment variable that we created during mutation to hold the original value?
                const backupEvName = `${evtr.name}${Patcher.EnvironmentVariableBackupSuffix}`;
                const backupEv: IEnvironmentVariable = container.env?.find(e => e.name === backupEvName);
                if(backupEv) {
                    // there is, restore its value into the primary environment variable, and remove the backup one

                    // make the backup one into the primary
                    backupEv.name = backupEv.name.replace(Patcher.EnvironmentVariableBackupSuffix, "");

                    // remove the old primary one
                    container.env?.splice(evIndex, 1);
                } else {
                    // there is not, so this is either the original, never mutated, object, or a mutated objected where the original didn't have this environment varialbe specified
                    if(container.env?.find(ev => ev.name === this.MutatedMarkerEnvironmentVariableName)) {
                        // this is a mutated object, the original didn't have this variable so we must remove it during unpatching
                        container.env?.splice(evIndex, 1);
                    } else {
                        // this is an original, never mutated object, so keep this environment variable as-is
                        // do nothing
                    }
                }
            });

            // remove the marker environment variable
            const markerEvIndex: number = container.env?.findIndex(ev => ev.name === this.MutatedMarkerEnvironmentVariableName);
            if(markerEvIndex !== -1) {
                container.env?.splice(markerEvIndex, 1);
            }
                
            container.volumeMounts = container.volumeMounts?.filter(vm => !volumeMountsToRemove.find(vmtr => vm.name === vmtr.name));
        });
    }
}
