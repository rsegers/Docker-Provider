package main

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"math"
	"net"
	"net/http"
	_ "net/http/pprof"
	"net/url"
	"os"
	"runtime/debug"
	"strconv"
	"strings"
	"time"

	"github.com/fluent/fluent-bit-go/output"
	"github.com/google/uuid"

	"Docker-Provider/source/plugins/go/input/lib"

	lumberjack "gopkg.in/natefinch/lumberjack.v2"
)

var (
	tokenResourceURL              string
	tokenResourceAudience         string
	grantType                     string
	azureJSONPath                 string
	publicMetricsEndpointTemplate string
	postRequestURLTemplate        string
	aadTokenURLTemplate           string
	msiEndpointTemplate           string
	imdsMsiEndpointTemplate       string
	userAssignedClientID          string
	postRequestURI                *url.URL
	recordBatchSize               int
	tokenRefreshBackOffInterval   time.Duration

	dataHash                         map[string]interface{}
	parsedTokenURI                   *url.URL
	tokenExpiryTime                  time.Time
	cachedAccessToken                string
	lastPostAttemptTime              time.Time
	firstPostAttemptMade             bool
	canSendDataToMDM                 bool
	lastTelemetrySentTime            time.Time
	useMsi                           bool
	isAADMSIAuth                     bool
	isWindows                        bool
	metricsFlushedCount              int
	isArcK8sCluster                  bool
	getAccessTokenBackoffExpiry      time.Time
	mdmExceptionsHash                map[string]int
	mdmExceptionsCount               int
	mdmExceptionTelemetryTimeTracker int64
	proxyEndpoint                    string // Proxy endpoint in format http(s)://<user>:<pwd>@<proxyserver>:<port>
	controllerType                   string = strings.ToLower(os.Getenv("CONTROLLER_TYPE"))
	metricsToCollectHash             map[string]bool

	containerResourceUtilTelemetryTimeTracker int64
	pvUsageTelemetryTimeTracker               int64
	containersExceededCpuThreshold            bool
	containersExceededMemRssThreshold         bool
	containersExceededMemWorkingSetThreshold  bool
	pvExceededUsageThreshold                  bool
	cpuCapacity                               float64
	memoryCapacity                            float64
	cpuAllocatable                            float64
	memoryAllocatable                         float64
	containerCpuLimitHash                     map[string]float64
	containerMemoryLimitHash                  map[string]float64
	containerResourceDimensionHash            map[string]string
	metricsThresholdHash                      map[string]float64
	processIncomingStream                     bool
	clusterIdentity                           *lib.ArcK8sClusterIdentity
)

var (
	// FLBLogger stream
	FLBLogger = lib.CreateLogger("/var/opt/microsoft/docker-cimprov/log/fluent-bit-mdm.log")
	// Log wrapper function
	Log = FLBLogger.Printf
)

func createLogger() *log.Logger {
	var logfile *os.File

	osType := os.Getenv("OS_TYPE")

	var logPath string

	if strings.Compare(strings.ToLower(osType), "windows") != 0 {
		logPath = "/var/opt/microsoft/docker-cimprov/log/fluent-bit-out-oms-runtime.log"
	} else {
		logPath = "/etc/amalogswindows/fluent-bit-out-oms-runtime.log"
	}

	if _, err := os.Stat(logPath); err == nil {
		fmt.Printf("File Exists. Opening file in append mode...\n")
		logfile, err = os.OpenFile(logPath, os.O_APPEND|os.O_WRONLY, 0600)
		if err != nil {
			lib.SendException(err.Error())
			fmt.Print(err.Error())
		}
	}

	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		fmt.Printf("File Doesnt Exist. Creating file...\n")
		logfile, err = os.Create(logPath)
		if err != nil {
			lib.SendException(err.Error())
			fmt.Print(err.Error())
		}
	}

	logger := log.New(logfile, "", 0)

	logger.SetOutput(&lumberjack.Logger{
		Filename:   logPath,
		MaxSize:    10, //megabytes
		MaxBackups: 1,
		MaxAge:     28,   //days
		Compress:   true, // false by default
	})

	logger.SetFlags(log.Ltime | log.Lshortfile | log.LstdFlags)
	return logger
}

func init() {
	tokenResourceURL = "https://monitoring.azure.com/"
	tokenResourceAudience = "https://monitor.azure.com/"
	grantType = "client_credentials"
	azureJSONPath = "/etc/kubernetes/host/azure.json"
	publicMetricsEndpointTemplate = "https://%s.monitoring.azure.com"
	postRequestURLTemplate = "%s%s/metrics"
	aadTokenURLTemplate = "https://login.microsoftonline.com/%s/oauth2/token"
	msiEndpointTemplate = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&client_id=%s&resource=%s"
	imdsMsiEndpointTemplate = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=%s"
	userAssignedClientID = os.Getenv("USER_ASSIGNED_IDENTITY_CLIENT_ID")
	recordBatchSize = 2000
	tokenRefreshBackOffInterval = 30 * time.Minute

	dataHash = make(map[string]interface{})
	tokenExpiryTime = time.Now()
	cachedAccessToken = ""
	lastPostAttemptTime = time.Now()
	firstPostAttemptMade = false
	canSendDataToMDM = true
	useMsi = false
	isAADMSIAuth = false
	isWindows = false
	metricsFlushedCount = 0
	isArcK8sCluster = false
	getAccessTokenBackoffExpiry = time.Now()
	mdmExceptionsHash = make(map[string]int)
	mdmExceptionsCount = 0
	mdmExceptionTelemetryTimeTracker = time.Now().Unix()
}

// InitializePlugin reads and populates plugin configuration
func InitializePlugin(agentVersion string) {
	go func() {
		isTest := os.Getenv("ISTEST")
		if strings.Compare(strings.ToLower(strings.TrimSpace(isTest)), "true") == 0 {
			e1 := http.ListenAndServe("localhost:6060", nil)
			if e1 != nil {
				Log("HTTP Listen Error: %s \n", e1.Error())
			}
		}
	}()

	// pluginConfig, err := ReadConfiguration(pluginConfPath)
	// if err != nil {
	// 	message := fmt.Sprintf("Error Reading plugin config path : %s \n", err.Error())
	// 	Log(message)
	// 	SendException(message)
	// 	time.Sleep(30 * time.Second)
	// 	log.Fatalln(message)
	// }

	aksResourceID := os.Getenv("AKS_RESOURCE_ID")
	aksRegion := os.Getenv("AKS_REGION")

	if aksResourceID == "" {
		log.Println("Environment Variable AKS_RESOURCE_ID is not set..")
		canSendDataToMDM = false
	} else if !strings.Contains(strings.ToLower(aksResourceID), "/microsoft.containerservice/managedclusters/") &&
		!strings.Contains(strings.ToLower(aksResourceID), "/microsoft.kubernetes/connectedclusters/") &&
		!strings.Contains(strings.ToLower(aksResourceID), "/microsoft.hybridcontainerservice/provisionedclusters/") {
		log.Printf("MDM Metrics not supported for this cluster type resource: %s\n", aksResourceID)
		canSendDataToMDM = false
	}

	if aksRegion == "" {
		log.Println("Environment Variable AKS_REGION is not set..")
		canSendDataToMDM = false
	} else {
		aksRegion = strings.ReplaceAll(aksRegion, " ", "")
	}

	if !canSendDataToMDM {
		log.Println("MDM Metrics not supported for this cluster")
		return
	}

	isWindows = strings.Contains(strings.ToLower(os.Getenv("OS_TYPE")), "windows")
	isAADMSIAuth = false
	if strings.Compare(strings.ToLower(os.Getenv(AADMSIAuthMode)), "true") == 0 {
		isAADMSIAuth = true
		Log("AAD MSI Auth Mode Configured")
	}

	log.Printf("MDM Metrics supported in %s region\n", aksRegion)

	if strings.Contains(strings.ToLower(aksResourceID), "microsoft.kubernetes/connectedclusters") ||
		strings.Contains(strings.ToLower(aksResourceID), "microsoft.hybridcontainerservice/provisionedclusters") {
		isArcK8sCluster = true
	}

	customMetricsEndpoint := os.Getenv("CUSTOM_METRICS_ENDPOINT")
	var metricsEndpoint string
	if customMetricsEndpoint != "" {
		metricsEndpoint = strings.TrimSpace(customMetricsEndpoint)
		// URL parsing for validation
		if _, err := url.Parse(metricsEndpoint); err != nil {
			log.Printf("Error parsing CUSTOM_METRICS_ENDPOINT: %v\n", err)
			return
		}
	} else {
		metricsEndpoint = fmt.Sprintf(publicMetricsEndpointTemplate, aksRegion)
	}
	postRequestURL := fmt.Sprintf(postRequestURLTemplate, metricsEndpoint, aksResourceID)
	var err error
	postRequestURI, err = url.Parse(postRequestURL)
	if err != nil {
		log.Printf("Error parsing post request URL: %v\n", err)
		return
	}

	if lib.IsIgnoreProxySettings() {
		Log("Ignoring reading of proxy configuration since ignoreProxySettings is true")
	} else {
		// read proxyEndpoint if proxy configured
		proxyEndpoint = ""
		if isWindows {
			proxyEndpoint = os.Getenv("PROXY")

		} else {
			proxyEndpoint, err = lib.GetProxyEndpoint()
			//TODO handle err
		}

	}
	// TODO: set proxy and application insights event

	if isArcK8sCluster {
		if isAADMSIAuth && !isWindows {
			log.Println("using IMDS sidecar endpoint for MSI token since its Arc k8s and Linux node")
			useMsi = true

			customResourceEndpoint := os.Getenv("customResourceEndpoint")
			if customResourceEndpoint != "" {
				tokenResourceAudience = strings.TrimSpace(customResourceEndpoint)
			}

			msiEndpoint := strings.Replace(imdsMsiEndpointTemplate, "%{resource}", tokenResourceAudience, 1)
			var err error
			parsedTokenURI, err = url.Parse(msiEndpoint)
			if err != nil {
				log.Printf("Error parsing MSI endpoint URL: %v\n", err)
			}
		} else {
			log.Println("using cluster identity token since cluster is azure arc k8s cluster")
			clusterIdentity = lib.NewArcK8sClusterIdentity()
		}
	} else {
		fileContent, err := os.ReadFile(azureJSONPath)
		if err != nil {
			log.Printf("Error reading Azure JSON file: %v\n", err)
			return
		}

		var dataHash map[string]interface{}
		if err := json.Unmarshal(fileContent, &dataHash); err != nil {
			log.Printf("Error parsing JSON file: %v\n", err)
			return
		}

		spClientID, _ := dataHash["aadClientId"].(string)

		if spClientID != "" && strings.ToLower(spClientID) != "msi" {
			useMsi = false
			aadTokenURL := strings.Replace(aadTokenURLTemplate, "%{tenant_id}", dataHash["tenantId"].(string), 1)
			parsedTokenURI, err = url.Parse(aadTokenURL)
			if err != nil {
				log.Printf("Error parsing AAD token URL: %v\n", err)
			}
		} else {
			useMsi = true
			msiEndpoint := strings.Replace(imdsMsiEndpointTemplate, "%{resource}", tokenResourceAudience, 1)
			if userAssignedClientID != "" {
				msiEndpoint = strings.Replace(msiEndpointTemplate, "%{user_assigned_client_id}", userAssignedClientID, 1)
				msiEndpoint = strings.Replace(msiEndpoint, "%{resource}", tokenResourceURL, 1)
			}
			parsedTokenURI, err = url.Parse(msiEndpoint)
			if err != nil {
				log.Printf("Error parsing MSI endpoint URL: %v\n", err)
			}
		}
	}
}

func PostToMDM(records []*GenericMetricTemplate) error {
	flushMDMExceptionTelemetry()

	// Check conditions for posting data
	now := time.Now()
	if (!firstPostAttemptMade || now.After(lastPostAttemptTime.Add(retryMDMPostWaitMinutes*time.Minute))) && canSendDataToMDM {
		var postBody []string
		// Assuming chunk is a type that can range over records (implementation depends on your data structure)
		for _, record := range records {
			jsonRecord, err := json.Marshal(record) // Assuming record can be marshalled to JSON
			if err != nil {
				return err
			}
			postBody = append(postBody, string(jsonRecord))
		}

		// Batch processing
		for count := len(postBody); count > 0; {
			currentBatchSize := math.Min(float64(count), float64(recordBatchSize))
			currentBatch := postBody[:int(currentBatchSize)]
			postBody = postBody[int(currentBatchSize):]
			count -= int(currentBatchSize)

			err := PostToMDMHelper(currentBatch)
			if err != nil {
				return err // Handle or log the error as appropriate
			}
		}
	} else {
		if !canSendDataToMDM {
			log.Printf("Cannot send data to MDM since all required conditions were not met")
		} else {
			timeSinceLastAttempt := now.Sub(lastPostAttemptTime).Minutes()
			log.Printf("Last Failed POST attempt to MDM was made %.1f min ago. This is less than the current retry threshold of %d min. NO-OP", timeSinceLastAttempt, retryMDMPostWaitMinutes)
		}
	}

	return nil
}

func PostToMDMHelper(batch []string) error {
	var access_token string
	if isArcK8sCluster {
		if isAADMSIAuth && !isWindows {
			access_token = getAccessToken()
		} else {
			if clusterIdentity == nil {
				clusterIdentity = lib.NewArcK8sClusterIdentity()
			}
			var err error
			access_token, err = clusterIdentity.GetClusterIdentityToken()
			if err != nil {
				return err
			}
		}
	} else {
		access_token = getAccessToken()
	}

	var httpClient *http.Client

	if proxyEndpoint == "" {
		httpClient = &http.Client{}
	} else {
		aksResourceID := os.Getenv("AKS_RESOURCE_ID")
		log.Printf("Proxy configured on this cluster: %s\n", aksResourceID)
		proxyURL, err := url.Parse(proxyEndpoint)
		if err != nil {
			log.Printf("Error parsing proxy URL: %v\n", err)
			return err
		}
		httpClient = &http.Client{
			Transport: &http.Transport{
				Proxy: http.ProxyURL(proxyURL),
			},
		}
	}

	httpClient.Transport = &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}

	requestId := uuid.New().String()
	postBody := strings.Join(batch, "\n")
	requestSizeKB := len(postBody) / 1024
	request, err := http.NewRequest("POST", postRequestURI.String(), bytes.NewBuffer([]byte(postBody)))
	if err != nil {
		log.Printf("Error creating new request: %v", err)
		return err
	}
	request.Header.Set("Content-Type", "application/x-ndjson")
	request.Header.Set("Authorization", "Bearer "+access_token)
	request.Header.Set("x-request-id", requestId)

	log.Printf("REQUEST BODY SIZE %d KB for requestId: %s\n", requestSizeKB, requestId)

	response, err := httpClient.Do(request)
	if err != nil {
		log.Printf("Error sending request: %v", err)
		handleError(err, response, requestId)
		return err
	}
	defer response.Body.Close()
	log.Printf("HTTP Post Response Code: %d for requestId: %s\n", response.StatusCode, requestId)
	if lastTelemetrySentTime.IsZero() || lastTelemetrySentTime.Add(60*time.Minute).Before(time.Now()) {
		lib.SendCustomEvent("AKSCustomMetricsMDMSendSuccessful", nil)
		lastTelemetrySentTime = time.Now()
	}

	return nil
}

func handleError(err error, response *http.Response, requestId string) {
	if response != nil && response.Body != nil {
		bodyBytes, _ := ioutil.ReadAll(response.Body)
		log.Printf("Failed to Post Metrics to MDM for requestId: %s, exception: %v, Response.body: %s", requestId, err, string(bodyBytes))
	} else {
		log.Printf("Failed to Post Metrics to MDM for requestId: %s, exception: %v", requestId, err)
	}
	stackTrace := debug.Stack()
	log.Printf("%s\n", string(stackTrace))

	if response != nil {
		statusCode := response.StatusCode
		switch {
		case statusCode == http.StatusForbidden:
			log.Printf("Response Code %d for requestId: %s, Updating last post attempt time", statusCode, requestId)
			lastPostAttemptTime = time.Now()
			firstPostAttemptMade = true
		case statusCode >= 400 && statusCode < 500:
			log.Printf("Non-retryable HTTPClientException when POSTing Metrics to MDM for requestId: %s, exception: %v, Response: %v", requestId, err, response)
		default:
			log.Printf("HTTPServerException when POSTing Metrics to MDM for requestId: %s, exception: %v, Response: %v", requestId, err, response)
		}
	}

	exceptionAggregator(err)

	// Additional logic for handling Errno::ETIMEDOUT and generic exceptions
	if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
		log.Printf("Timed out when POSTing Metrics to MDM for requestId: %s, exception: %v", requestId, err)
		stackTrace := debug.Stack()
		log.Printf("%s\n", string(stackTrace))
	} else if err != nil {
		log.Printf("Exception POSTing Metrics to MDM for requestId: %s, exception: %v", requestId, err)
		stackTrace := debug.Stack()
		log.Printf("%s\n", string(stackTrace))
	}

}

func exceptionAggregator(err error) {
	if err != nil {
		exceptionKey := err.Error()
		mdmExceptionsHash[exceptionKey]++
		mdmExceptionsCount++
	}
}

func getAccessToken() string {
	var accessToken string
	var err error
	var retries int = 0
	for ; retries < 2; retries++ {
		accessToken, err = getAccessTokenHelper()
		if err != nil {
			log.Printf("Error getting access token: %v\n", err)
			log.Printf("Retrying request to get token - retry number: %d\n", retries)
			time.Sleep(time.Duration(retries) * time.Second)
			continue
		}
	}
	if err != nil && retries >= 2 {
		getAccessTokenBackoffExpiry = time.Now().Add(tokenRefreshBackOffInterval)
		log.Printf("getAccessTokenBackoffExpiry set to: %s\n", getAccessTokenBackoffExpiry)
		lib.SendExceptionTelemetry(err.Error(), map[string]string{"FeatureArea": "MDM"})
	}
	return accessToken
}

func getAccessTokenHelper() (token string, err error) {
	if !time.Now().After(getAccessTokenBackoffExpiry) {
		return cachedAccessToken, nil
	}

	var httpAccessToken *http.Client
	var tokenRequest *http.Request
	properties := map[string]string{}
	if cachedAccessToken == "" || time.Now().Add(5*time.Minute).After(tokenExpiryTime) {
		log.Println("Refreshing access token for out_mdm plugin..")
		if isAADMSIAuth {
			properties["isMSI"] = "true"
		}
		if isAADMSIAuth && isWindows {
			log.Println("Reading the token from IMDS token file since it's Windows..")
			if tokenContent, err := ioutil.ReadFile("c:/etc/imds-access-token/token"); err == nil {
				var parsedJson map[string]interface{}
				if err := json.Unmarshal(tokenContent, &parsedJson); err == nil {
					tokenExpiryTime = time.Now().Add(tokenRefreshBackOffInterval)
					cachedAccessToken = parsedJson["access_token"].(string)
					log.Println("Successfully got access token")
					lib.SendCustomEvent("AKSCustomMetricsMDMToken-MSI", properties)
				} else {
					log.Println("Error parsing the token file content: ", err)
					return "", err
				}
			} else {
				log.Println("either MSI Token file path doesn't exist or not readable: ", err)
				return "", err
			}
		} else {
			if useMsi {
				log.Println("Using MSI to get the token to post MDM data")
				lib.SendCustomEvent("AKSCustomMetricsMDMToken-MSI", properties)

				httpAccessToken = &http.Client{}
				tokenRequest, err = http.NewRequest("GET", parsedTokenURI.String(), nil)
				if err != nil {
					log.Printf("Error creating request: %v\n", err)
					return
				}
				tokenRequest.Header.Set("Metadata", "true")
			} else {
				log.Println("Using SP to get the token to post MDM data")
				lib.SendCustomEvent("AKSCustomMetricsMDMToken-SP", properties)

				httpAccessToken = &http.Client{Transport: &http.Transport{
					TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
				}}
				formData := url.Values{
					"grant_type":    {grantType},
					"client_id":     {dataHash["aadClientId"].(string)},
					"client_secret": {dataHash["aadClientSecret"].(string)},
					"resource":      {tokenResourceURL},
				}
				tokenRequest, err = http.NewRequest("POST", parsedTokenURI.String(), bytes.NewBufferString(formData.Encode()))
				if err != nil {
					log.Printf("Error creating request: %v\n", err)
					return
				}
				tokenRequest.Header.Set("Content-Type", "application/x-www-form-urlencoded")
			}

			log.Println("Making request to get token..")
			tokenResponse, err := httpAccessToken.Do(tokenRequest)
			if err != nil {
				log.Printf("Error sending request: %v\n", err)
				return "", err
			}
			defer tokenResponse.Body.Close()

			responseBody, err := ioutil.ReadAll(tokenResponse.Body)
			if err != nil {
				log.Printf("Error reading response body: %v\n", err)
				return "", err
			}

			var parsedJSON map[string]interface{}
			err = json.Unmarshal(responseBody, &parsedJSON)
			if err != nil {
				log.Printf("Error parsing JSON response: %v\n", err)
				return "", err
			}

			if accessToken, ok := parsedJSON["access_token"].(string); ok {
				cachedAccessToken = accessToken
				tokenExpiryTime = time.Now().Add(tokenRefreshBackOffInterval)
				log.Println("Successfully got access token")
			} else {
				log.Println("Error: access token not found in response")
				return "", errors.New("access token not found in response")
			}
		}

	}
	return cachedAccessToken, nil
}

func flushMDMExceptionTelemetry() {
	timeDifference := math.Abs(float64(time.Now().Unix()) - float64(mdmExceptionTelemetryTimeTracker))
	timeDifferenceInMinutes := timeDifference / 60
	if timeDifferenceInMinutes > MDM_EXCEPTIONS_METRIC_FLUSH_INTERVAL {
		telemetryProperties := map[string]string{}
		telemetryProperties["ExceptionsHashForFlushInterval"] = fmt.Sprintf("%v", mdmExceptionsHash)
		telemetryProperties["FlushInterval"] = fmt.Sprintf("%v", MDM_EXCEPTIONS_METRIC_FLUSH_INTERVAL)
		lib.SendMetricTelemetry("AKSCustomMetricsMdmExceptions", float64(mdmExceptionsCount), telemetryProperties)
		mdmExceptionsCount = 0
		mdmExceptionsHash = make(map[string]int)
		mdmExceptionTelemetryTimeTracker = time.Now().Unix()
	}
}

func PostCAdvisorMetricsToMDM(records []map[interface{}]interface{}) int {
	Log("PostCAdvisorMetricsToMDM::Info:PostCAdvisorMetricsToMDM starting")
	if (records == nil) || !(len(records) > 0) {
		Log("PostCAdvisorMetricsToMDM::Error:no records")
		return output.FLB_OK
	}
	processIncomingStream = CheckCustomMetricsAvailability()
	metricsToCollectHash = make(map[string]bool)
	for _, metric := range strings.Split(metricsToCollect, ",") {
		metricsToCollectHash[metric] = true
	}
	log.Printf("After check_custom_metrics_availability process_incoming_stream is %v", processIncomingStream)

	containerResourceUtilTelemetryTimeTracker = time.Now().Unix()
	pvUsageTelemetryTimeTracker = time.Now().Unix()

	containersExceededCpuThreshold = false
	containersExceededMemRssThreshold = false
	containersExceededMemWorkingSetThreshold = false
	pvExceededUsageThreshold = false

	if processIncomingStream {
		cpuCapacity = 0.0
		cpuAllocatable = 0.0
		memoryCapacity = 0.0
		memoryAllocatable = 0.0
		ensureCPUMemoryCapacityAndAllocatableSet()
		containerCpuLimitHash = make(map[string]float64)
		containerMemoryLimitHash = make(map[string]float64)
		containerResourceDimensionHash = make(map[string]string)
		metricsThresholdHash = GetContainerResourceUtilizationThresholds()
	}

	// TODO why twice?
	ensureCPUMemoryCapacityAndAllocatableSet()
	if processIncomingStream {
		var err error
		containerCpuLimitHash, containerMemoryLimitHash, containerResourceDimensionHash, err = GetAllContainerLimits()
		if err != nil {
			log.Printf("Error getting container limits: %v", err)
			lib.SendExceptionTelemetry(err.Error(), nil)
		}
	}

	var mdmMetrics []*GenericMetricTemplate
	for _, record := range records {
		filtered_records, err := filterCAdvisor2MDM(record)
		if err != nil {
			message := fmt.Sprintf("PostTelegrafMetricsToMDM::Error:when processing telegraf metric %q", err)
			Log(message)
			lib.SendException(message)
		}
		mdmMetrics = append(mdmMetrics, filtered_records...)
	}
	err := PostToMDM(mdmMetrics)
	if err != nil {
		Log("PostTelegrafMetricsToMDM::Error:Failed to post to MDM %v", err)
		return output.FLB_RETRY
	}

	return output.FLB_OK
}

func filterCAdvisor2MDM(record map[interface{}]interface{}) ([]*GenericMetricTemplate, error) {
	if !processIncomingStream {
		return nil, nil
	}

	convertedRecord := ConvertMap(record)

	if strings.EqualFold(convertedRecord["name"], PVUsedBytes) {
		return filterPVInsightsMetrics(convertedRecord)
	}

	// TODO: is below defer needed?
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Error processing cadvisor metrics record: %v", r)
			lib.SendExceptionTelemetry(fmt.Sprintf("%v", r), nil)
		}
	}()

	objectName := convertedRecord["ObjectName"]

	var collections []map[string]interface{}
	err := json.Unmarshal([]byte(convertedRecord["json_Collections"]), &collections)
	if err != nil {
		log.Fatalf("Error parsing json_Collections: %v", err)
	}

	counterName := collections[0]["CounterName"].(string)

	percentageMetricValue := 0.0
	allocatablePercentageMetricValue := 0.0
	metricValue := collections[0]["Value"].(float64)

	if objectName == objectNameK8sNode && metricsToCollectHash[strings.ToLower(counterName)] {
		var metricName string
		if counterName == CPUUsageNanoCores {
			metricName = CPUUsageMilliCores
			metricValue = metricValue / 1000000
			var targetNodeCpuCapacityMC float64
			var targetNodeCpuAllocatableMc float64
			// TODO: is the below needed? earlier this replicaset check was to get windows ds data

			// if controllerType == "replicaset" {
			// 	targetNodeCpuCapacityMC =  nil //TODO
			// 	targetNodeCpuAllocatableMc = 0.0
			// } else {
			// 	targetNodeCpuCapacityMC = cpuCapacity
			// 	targetNodeCpuAllocatableMc = cpuAllocatable
			// }
			targetNodeCpuCapacityMC = cpuCapacity
			targetNodeCpuAllocatableMc = cpuAllocatable

			log.Printf("Metric value: %f CPU Capacity %f CPU Allocatable %f", metricValue, targetNodeCpuCapacityMC, targetNodeCpuAllocatableMc)
			if targetNodeCpuCapacityMC != 0.0 {
				percentageMetricValue = (metricValue / targetNodeCpuCapacityMC) * 100
			}
			if targetNodeCpuAllocatableMc != 0.0 {
				allocatablePercentageMetricValue = (metricValue / targetNodeCpuAllocatableMc) * 100
			}
		}

		if strings.HasPrefix(counterName, "memory") {
			metricName = counterName
			var targetNodeMemoryCapacity float64
			var targetNodeMemoryAllocatable float64
			// TODO: is the below needed? earlier this replicaset check was to get windows ds data

			// if controllerType == "replicaset" {
			// 	targetNodeMemoryCapacity = nil // TODO
			// 	targetNodeMemoryAllocatable = 0.0
			// } else {
			// 	targetNodeMemoryCapacity = memoryCapacity
			// 	targetNodeMemoryAllocatable = memoryAllocatable
			// }
			targetNodeMemoryCapacity = memoryCapacity
			targetNodeMemoryAllocatable = memoryAllocatable

			log.Printf("Metric_value: %f Memory Capacity %f Memory Allocatable %f", metricValue, targetNodeMemoryCapacity, targetNodeMemoryAllocatable)

			if targetNodeMemoryCapacity != 0.0 {
				percentageMetricValue = (metricValue / targetNodeMemoryCapacity) * 100
			}
			if targetNodeMemoryAllocatable != 0.0 {
				allocatablePercentageMetricValue = (metricValue / targetNodeMemoryAllocatable) * 100
			}
		}

		log.Printf("percentage_metric_value for metric: %s for instance: %s percentage: %f allocatable_percentage: %f", metricName, record["Host"], percentageMetricValue, allocatablePercentageMetricValue)

		if percentageMetricValue > 100.0 {
			telemetryProperties := map[string]string{}
			telemetryProperties["Computer"] = record["Host"].(string)
			telemetryProperties["MetricName"] = metricName
			telemetryProperties["MetricPercentageValue"] = strconv.FormatFloat(percentageMetricValue, 'f', -1, 64)
			lib.SendCustomEvent("ErrorPercentageOutOfBounds", telemetryProperties)
		}

		if allocatablePercentageMetricValue > 100.0 {
			telemetryProperties := map[string]string{}
			telemetryProperties["Computer"] = record["Host"].(string)
			telemetryProperties["MetricName"] = metricName
			telemetryProperties["MetricAllocatablePercentageValue"] = strconv.FormatFloat(allocatablePercentageMetricValue, 'f', -1, 64)
			lib.SendCustomEvent("ErrorPercentageOutOfBounds", telemetryProperties)
		}

		return GetNodeResourceMetricRecords(record, metricName, metricValue, percentageMetricValue, allocatablePercentageMetricValue)
	} else if objectName == ObjectNameK8SContainer && metricsToCollectHash[strings.ToLower(counterName)] {
		instanceName := record["InstanceName"].(string)
		metricName := counterName
		// Using node cpu capacity in the absence of container cpu capacity since the container will end up using the
		// node's capacity in this case. Converting this to nanocores for computation purposes, since this is in millicores
		containerCpuLimit := cpuCapacity * 1000000
		containerMemoryLimit := memoryCapacity

		if counterName == CPUUsageNanoCores {
			if instanceName != "" {
				if val, ok := containerCpuLimitHash[instanceName]; ok {
					containerCpuLimit = val
				}
			}

			// Checking if KubernetesApiClient ran into error while getting the numeric value or if we failed to get the limit
			if containerCpuLimit != 0.0 {
				percentageMetricValue = (metricValue / containerCpuLimit) * 100
			}
		} else if strings.HasPrefix(counterName, "memory") {
			if instanceName != "" {
				if val, ok := containerMemoryLimitHash[instanceName]; ok {
					containerMemoryLimit = val
				}
			}

			// Checking if KubernetesApiClient ran into error while getting the numeric value or if we failed to get the limit
			if containerMemoryLimit != 0.0 {
				percentageMetricValue = (metricValue / containerMemoryLimit) * 100
			}
		}

		log.Printf("percentage_metric_value for metric: %s for instance: %s percentage: %f", metricName, instanceName, percentageMetricValue)
		log.Printf("metric_threshold_hash for %s: %f", metricName, metricsThresholdHash[metricName])
		thresholdPercentage := metricsThresholdHash[metricName]

		flushMetricTelemetry()
		if percentageMetricValue >= thresholdPercentage {
			setThresholdExceededTelemetry(metricName)
			return GetContainerResourceUtilMetricRecords(record["Timestamp"].(float64), metricName, percentageMetricValue, containerResourceDimensionHash[instanceName], thresholdPercentage, false)
		} else {
			return nil, nil
		}
	} else {
		return nil, nil
	}
}

func filterPVInsightsMetrics(record map[string]string) ([]*GenericMetricTemplate, error) {
	mdmMetrics := []*GenericMetricTemplate{}

	defer func() {
		if r := recover(); r != nil {
			log.Printf("Error processing insights metrics record: %v", r)
			lib.SendExceptionTelemetry(fmt.Sprintf("%v", r), nil)
			mdmMetrics = nil
		}
	}()

	if record["name"] == PVUsedBytes && metricsToCollectHash[strings.ToLower(record["name"])] {
		metricName := record["name"]
		usage := record["usage"]
		fUsage, _ := strconv.ParseFloat(usage, 64)

		var tags map[string]string
		err := json.Unmarshal([]byte(record["Tags"]), &tags)
		if err != nil {
			log.Printf("Error parsing tags: %v", err)
			lib.SendExceptionTelemetry(err.Error(), nil)
			return nil, err
		}

		fCapacity, _ := strconv.ParseFloat(tags[InsightsMetricsTagsPVCapacityBytes], 64)

		percentageMetricValue := 0.0
		if fCapacity != 0.0 {
			percentageMetricValue = (fUsage / fCapacity) * 100
		}
		log.Printf("percentage metric value for %s is %f", metricName, percentageMetricValue)
		log.Printf("metricsThresholdHash for %s is %f", metricName, metricsThresholdHash[metricName])

		computer := record["computer"]
		resourceDimensions := tags
		thresholdPercentage := metricsThresholdHash[metricName]

		flushMetricTelemetry()

		collectionTime, err := strconv.ParseFloat(record["CollectionTime"], 64)
		if err != nil {
			log.Printf("Error parsing CollectionTime: %v", err)
			lib.SendExceptionTelemetry(err.Error(), nil)
			return nil, err
		}

		if percentageMetricValue >= thresholdPercentage {
			setThresholdExceededTelemetry(metricName)
			return GetPVResourceUtilMetricRecords(collectionTime, metricName, computer, percentageMetricValue, resourceDimensions, thresholdPercentage, false)
		} else {
			return nil, nil
		}
	}

	return mdmMetrics, nil

}

func setThresholdExceededTelemetry(metricName string) {
	switch metricName {
	case CPUUsageNanoCores:
		containersExceededCpuThreshold = true
	case MemoryRssBytes:
		containersExceededMemRssThreshold = true
	case MemoryWorkingSetBytes:
		containersExceededMemWorkingSetThreshold = true
	case PVUsedBytes:
		pvExceededUsageThreshold = true
	}
}

func flushMetricTelemetry() {
	timeDifference := math.Abs(float64(time.Now().Unix()) - float64(containerResourceUtilTelemetryTimeTracker))
	timeDifferenceInMinutes := timeDifference / 60
	if timeDifferenceInMinutes > TelemetryFlushIntervalInMinutes {
		properties := map[string]string{}
		properties["CpuThresholdPercentage"] = strconv.FormatFloat(metricsThresholdHash[CPUUsageNanoCores], 'f', -1, 64)
		properties["MemoryRssThresholdPercentage"] = strconv.FormatFloat(metricsThresholdHash[MemoryRssBytes], 'f', -1, 64)
	}
}

func ensureCPUMemoryCapacityAndAllocatableSet() {
	if controllerType == "replicaset" {
		if cpuCapacity != 0.0 && memoryCapacity != 0.0 {
			log.Printf("CPU And Memory Capacity are already set and their values are as follows cpu_capacity : %f, memory_capacity: %f", cpuCapacity, memoryCapacity)
			return
		}
	} else if controllerType == "daemonset" {
		if cpuCapacity != 0.0 && memoryCapacity != 0.0 && cpuAllocatable != 0.0 && memoryAllocatable != 0.0 {
			log.Printf("CPU And Memory Capacity are already set and their values are as follows cpu_capacity : %f, memory_capacity: %f", cpuCapacity, memoryCapacity)
			log.Printf("CPU And Memory Allocatable are already set and their values are as follows cpu_allocatable : %f, memory_allocatable: %f", cpuAllocatable, memoryAllocatable)
			return
		}
	}

	if controllerType == "replicaset" {
		log.Printf("ensure_cpu_memory_capacity_set cpu_capacity %f memory_capacity %f", cpuCapacity, memoryCapacity)

		resourceUri := lib.GetNodesResourceUri("nodes?fieldSelector=metadata.name%3D" + os.Getenv("HOSTNAME"))
		nodeInventory, err := lib.GetKubeResourceInfo(resourceUri)
		if err != nil {
			log.Printf("Error when getting nodeInventory from kube API: %v", err)
			lib.SendExceptionTelemetry(err.Error(), nil)
			return
		}

		if nodeInventory != nil {
			cpuCapacityJSON, err := ParseNodeLimits(nodeInventory, "capacity", "cpu", "cpuCapacityNanoCores", time.Now().UTC().Format(time.RFC3339))
			if err != nil {
				log.Println("Error getting cpu_capacity:", err)
			} else if len(cpuCapacityJSON) > 0 {
				var metricVal struct {
					Value string `json:"Value"`
				}

				jsonCollections, ok := cpuCapacityJSON[0]["json_Collections"].(string)
				if !ok {
					log.Println("Error getting cpu capacity JSON")
				} else {
					err := json.Unmarshal([]byte(jsonCollections), &metricVal)
					if err != nil {
						log.Println("Error parsing cpu capacity JSON:", err)
					} else {
						cpuCapacity, _ = strconv.ParseFloat(metricVal.Value, 64)
						log.Println("CPU Limit", cpuCapacity)
					}
				}
			} else {
				log.Println("Error getting cpu_capacity")
			}

			memoryCapacityJSON, err := ParseNodeLimits(nodeInventory, "capacity", "memory", "memoryCapacityBytes", time.Now().UTC().Format(time.RFC3339))
			if err != nil {
				log.Println("Error getting memory_capacity:", err)
			} else if len(memoryCapacityJSON) > 0 {
				var metricVal struct {
					Value string `json:"Value"`
				}

				jsonCollections, ok := memoryCapacityJSON[0]["json_Collections"].(string)
				if !ok {
					log.Println("Error getting memory capacity JSON")
				} else {
					jsonBytes := []byte(jsonCollections)
					err := json.Unmarshal(jsonBytes, &metricVal)
					if err != nil {
						log.Println("Error parsing memory capacity JSON:", err)
					} else {
						memoryCapacity, _ = strconv.ParseFloat(metricVal.Value, 64)
						log.Println("Memory Limit", memoryCapacity)
					}
				}
			} else {
				log.Println("Error getting memory_capacity")
			}
		}
	} else if controllerType == "daemonset" {
		var err error
		cpuCapacity, memoryCapacity, err = GetNodeCapacity()
		if err != nil {
			log.Println("Error getting capacity_from_kubelet: cpu_capacity and memory_capacity")
			lib.SendExceptionTelemetry(err.Error(), nil)
			return
		}
		cpuAllocatable, memoryAllocatable, err = GetNodeAllocatable(cpuCapacity, memoryCapacity)
		if err != nil {
			log.Println("Error getting allocatable_from_kubelet: cpu_allocatable and memory_allocatable")
			lib.SendExceptionTelemetry(err.Error(), nil)
			return
		}
	}

}

func SendMDMMetrics(pushInterval string) {
	// TODO
}

func PostTelegrafMetricsToMDM(telegrafRecords []map[interface{}]interface{}) int {
	Log("PostTelegrafMetricsToMDM::Info:PostTelegrafMetricsToMDM starting")
	if (telegrafRecords == nil) || !(len(telegrafRecords) > 0) {
		Log("PostTelegrafMetricsToMDM::Error:no timeseries to derive")
		return output.FLB_OK
	}
	processIncomingStream := CheckCustomMetricsAvailability()

	if !processIncomingStream {
		Log("PostTelegrafMetricsToMDM::Info:Custom metrics is not enabled for this workspace. Skipping processing of incoming stream")
		return output.FLB_OK
	}

	var mdmMetrics []*GenericMetricTemplate

	for _, record := range telegrafRecords {
		filtered_records, err := filterTelegraf2MDM(record)
		if err != nil {
			message := fmt.Sprintf("PostTelegrafMetricsToMDM::Error:when processing telegraf metric %q", err)
			Log(message)
			lib.SendException(message)
		}
		mdmMetrics = append(mdmMetrics, filtered_records...)
	}

	err := PostToMDM(mdmMetrics)
	if err != nil {
		Log("PostTelegrafMetricsToMDM::Error:Failed to post to MDM %v", err)
		return output.FLB_RETRY
	}

	return output.FLB_OK
}

func filterTelegraf2MDM(record map[interface{}]interface{}) ([]*GenericMetricTemplate, error) {
	if strings.EqualFold(record["name"].(string), TelegrafDiskMetrics) {
		return GetDiskUsageMetricRecords(record)
	} else {
		return GetMetricRecords(record)
	}
}
