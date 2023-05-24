You can create the policy definition using a command like :

```az policy definition create --name "CITest" --display-name "CITest" --mode Indexed --metadata version=1.0.0 category=Kubernetes --rules .\azure-policy.rules.json --params .\azure-policy.parameters.json```

**NOTE**

- Please download all files under AddonPolicyTemplate folder before running the policy template.
- After creating the policy definition through the above command, go to Azure portal -> Policy -> Definitions and select the definition you just created.
- Click on 'Assign' and then go to the 'Parameters' tab and fill in the details. Then click 'Review + Create'.
- Now that the policy is assigned to the subscription, whenever you create a new cluster which does not have container insights enabled, the policy will run and deploy the resources. If you want to apply the policy to existing AKS cluster, create a 'Remediation task' for that resource after going to the 'Policy Assignment'.
