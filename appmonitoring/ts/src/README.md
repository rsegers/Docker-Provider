# MutatingWebhook


# Making a change to the image
1. Prepare a change in a branch made off of _ai_prod_ branch. All work is confined within _appmonitoring/ts/src_.
2. Make sure the branch builds locally with _build.cmd_.
3. Build and push the image to a test ACR by running _dockerBuild.cmd v0_ where _v0_ is the image tag.
4. Create a standalone environment of AKS RP to test the change, or test it directly on an AKS cluster by plugging the modified image into a test workload.
5. Merge a PR into the _ai_prod_ branch.
6. Prepare a GitHub release following the _semver_ conventions.
7. Build and push the image to MCR by running the [ContainerInsights-MultiArch-MergedBranches-AppMonitoring](https://github-private.visualstudio.com/microsoft/_build?definitionId=539) pipeline.
8. Merge a PR into the AKS RP repo that updates the version of the image used.
9. Follow daily and weekly rollouts of AKS RP and watch change propagation on the dashboard.