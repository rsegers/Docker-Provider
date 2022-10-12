package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"time"
)

const MDSDTenatDirectoryPath string = "/var/opt/microsoft/linuxmonagent/tenants"

var tenantConfig string = `### Geneva Linux Agent tenant settings file
TENANT_NAME=%[1]s
MDSD_VAR=/var/opt/microsoft/linuxmonagent/log
MDSD_CONFIG_DIR=/var/opt/microsoft/linuxmonagent/log/${TENANT_NAME}
MDSD_RUN_DIR=/var/run/mdsd/${TENANT_NAME}
MDSD_ROLE_PREFIX=${MDSD_RUN_DIR}/default

# This is where rsyslog and eventhub messages are spooled.
MDSD_SPOOL_DIRECTORY=${MDSD_VAR}/spool/${TENANT_NAME}

MDSD_LOG=/var/opt/microsoft/linuxmonagent/log
# Note: Don't set TCP ports, use instead the UNIX domain sockets already available under this folder $MDSD_RUN_DIR
# option –R will lookup for available port number
MDSD_OPTIONS="-A -c /etc/mdsd.d/mdsd.xml -C -d -r ${MDSD_ROLE_PREFIX} -S ${MDSD_SPOOL_DIRECTORY}/eh -R -e ${MDSD_LOG}/${TENANT_NAME}.err -w ${MDSD_LOG}/${TENANT_NAME}.warn -o ${MDSD_LOG}/${TENANT_NAME}.info"

# GCS settings
MONITORING_GCS_ENVIRONMENT=%[2]s
MONITORING_GCS_ACCOUNT=%[1]s
MONITORING_GCS_NAMESPACE=%[3]s
MONITORING_GCS_REGION=%[4]s
MONITORING_CONFIG_VERSION=2.0
MONITORING_USE_GENEVA_CONFIG_SERVICE=true
MONITORING_GCS_AUTH_ID_TYPE=AuthMSIToken
# Once GCS has support of AMCS Token audience and this is not required until then using it
MONITORING_GCS_AUTH_ID=%[5]s
# Both MONITORING_GCS_CERT_CERTFILE and MONITORING_GCS_CERT_KEYFILE not needed for auto-config
# MONITORING_GCS_CERT_CERTFILE=/etc/mdsd.d/gcscert.pem
# MONITORING_GCS_CERT_KEYFILE=/etc/mdsd.d/gcskey.pem
`

type GenevaConfigs struct {
	APIVersion string `json:"apiVersion"`
	Items      []struct {
		APIVersion string `json:"apiVersion"`
		Kind       string `json:"kind"`
		Metadata   struct {
			Name            string `json:"name"`
			Namespace       string `json:"namespace"`
			ResourceVersion string `json:"resourceVersion"`
			UID             string `json:"uid"`
		} `json:"metadata"`
		Spec struct {
			GenevaAccount         string `json:"genevaaccount"`
			GenevaEnvironmentType string `json:"genevaenvironmentType"`
			GenevaNamespace       string `json:"genevanamespace"`
		} `json:"spec"`
	} `json:"items"`
	Kind string `json:"kind"`
}

type GenevaAccountConfig struct {
	GenevaAccount         string
	GenevaNamespace       string
	GenevaEnvironmentType string
}

func genevaTenantConfigMgr() {
	for ; true; <-GenevaTenantConfigRefreshTicker.C {
		Log("genevaTenantConfigMgr: start")
		_k8sNamespaceGenevaAccountMap := make(map[string]string)
		var responseBytes []byte
		var errorMessage string
		var err error
		resourceRegion := os.Getenv("AKS_REGION")
		monitoringGCSAuthID := os.Getenv("MONITORING_GCS_AUTH_ID")
		for retryCount := 0; retryCount < MaxRetries; retryCount++ {
			responseBytes, err = ClientSet.RESTClient().Get().AbsPath("/apis/azmon.container.insights/v1/genevaconfigs").DoRaw(context.TODO())
			if err != nil {
				time.Sleep(time.Duration((retryCount+1)*100) * time.Millisecond)
				continue
			}
			break
		}
		if responseBytes != nil {
			var genevaconfigs GenevaConfigs
			//Log("genevaTenantConfigMgr: genevaconfig CRD response: %s", responseBytes)
			err = json.Unmarshal(responseBytes, &genevaconfigs)
			if err != nil {
				errorMessage = fmt.Sprintf("genevaTenantConfigMgr: Error unmarshalling the crdResponseBytes: %s", err.Error())
				Log(errorMessage)
			} else {
				Log("genevaTenantConfigMgr: genevaconfigs: %s", genevaconfigs)
				for _, item := range genevaconfigs.Items {
					createTenantConfigFileIfNotExists(item.Spec.GenevaAccount, item.Spec.GenevaEnvironmentType, item.Spec.GenevaNamespace, resourceRegion, monitoringGCSAuthID)
					_k8sNamespaceGenevaAccountMap[item.Metadata.Namespace] = item.Spec.GenevaAccount
				}
				Log("genevaTenantConfigMgr: Locking to update geneva tenant account config")
				GenevaConfigUpdateMutex.Lock()
				K8SNamespaceGenevaAccountMap = _k8sNamespaceGenevaAccountMap
				GenevaConfigUpdateMutex.Unlock()
				Log("genevaTenantConfigMgr: Unlocking to update geneva tenant account config")
			}
		} else {
			Log("genevaTenantConfigMgr: Error: got the responseBytes nil")
		}
		Log("genevaTenantConfigMgr: end")
	}
}

func createTenantConfigFileIfNotExists(gcsAccount, gcsEnvironment, gcsNamespace, region, monitoringGCSAuthID string) {
	tenantConfigFilePath := fmt.Sprintf("%s/%s", MDSDTenatDirectoryPath, gcsAccount)
	Log("createTenantConfigFileIfNotExists: start")
	if _, err := os.Stat(tenantConfigFilePath); errors.Is(err, os.ErrNotExist) {
		f, err := os.Create(tenantConfigFilePath)
		if err != nil {
			Log("createTenantConfigFileIfNotExists: Failed to create tenant config file: %s", err)
		}
		defer f.Close()
		tenantConfigFileContent := fmt.Sprintf(tenantConfig, gcsAccount, gcsEnvironment, gcsNamespace, region, monitoringGCSAuthID)
		_, err = f.WriteString(tenantConfigFileContent)
		if err != nil {
			Log("createTenantConfigFileIfNotExists: Failed to create tenant config file: %s", err)
		} else {
			Log("createTenantConfigFileIfNotExists: starting Tenant in this path: %s", tenantConfigFilePath)
			setTenant(tenantConfigFilePath)
		}
	}
	Log("genevaTenancreateTenantConfigFileIfNotExiststConfigMgr: end")
	//TODO - Tenant offboarding
}

func setTenant(tenantConfigFilePath string) {
	Log("setTenant: start")
	//args := fmt.Sprintf("set-tenant %s", tenantConfigFilePath)
	cmd := exec.Command("mdsdmgrctl", "set-tenant", tenantConfigFilePath)
	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err != nil {
		Log("setTenant: Failed to start tenant: %s", err)
	} else {
		Log("setTenant: started Tenant successfully using this path: %s", tenantConfigFilePath)
	}
	Log("setTenant: stdoutput of the exec command: %s", stdout.String())
	Log("setTenant: stderr of the exec command: %s", stderr.String())

	Log("setTenant: end")
}
