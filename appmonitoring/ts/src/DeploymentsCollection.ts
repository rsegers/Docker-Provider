import { Deployment } from "./RequestDefinition.js"

export class DeploymentsCollection {

    private deployments: Deployment[] = [];

    public ListDeployments(): Deployment[] {
        return this.deployments;
    }

    public GetDeployment(namespace: string, name: string): Deployment {
        return this.deployments.find(d => d.metadata.namespace === namespace && d.metadata.name === name, this);
    }

    public Upsert(deployment: Deployment): void {
        this.Remove(deployment);

        this.deployments.push(deployment);
    }

    public Remove(deployment: Deployment): void {
        for (let i = 0; i < this.deployments.length; i++) {
            if (this.deployments[i].metadata.name === deployment.metadata.name && this.deployments[i].metadata.namespace === deployment.metadata.namespace) {
                this.deployments.splice(i, 1);
                break;
            }
        }
    }
}