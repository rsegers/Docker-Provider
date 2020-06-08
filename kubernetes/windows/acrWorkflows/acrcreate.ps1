# create acr task for windows from ci_dev branch to create image in cidev repository
az acr task create -n createimagewincifeaturecidev -r containerinsightsprod -c https://github.com/microsoft/Docker-Provider.git --branch ci_dev --file kubernetes/windows/acrworkflows/acrwindowsdevnamespace.yaml --commit-trigger-enabled true --platform Windows/amd64 --git-access-token 00000000000000000000000000 --auth-mode Default --debug

# create acr task for windows from ci_prod branch to create image in ciprod repository
az acr task create -n createimagewincifeatureciprod -r containerinsightsprod -c https://github.com/microsoft/Docker-Provider.git --branch ci_prod --file kubernetes/windows/acrworkflows/acrwindowsprodnamespace.yaml --commit-trigger-enabled true --platform Windows/amd64 --git-access-token 00000000000000000000000000 --auth-mode Default --debug


# test task
az acr task create -n createimagewintestcidev -r containerinsightsprod -c https://github.com/microsoft/Docker-Provider.git --branch gangams/ci_dev --file kubernetes/windows/acrworkflows/acrwindowsdevnamespace.yaml --commit-trigger-enabled true --platform Windows/amd64 --git-access-token 00000000000000000000000000 --auth-mode Default --debug

