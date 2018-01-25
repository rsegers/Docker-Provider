#!/usr/local/bin/ruby

class CAdvisorMetricsAPIClient
    
            require 'json'
            require 'logger'
            require 'net/http'
            require 'net/https'
            require 'uri'
    
            require_relative 'oms_common'
    
            @LogPath = "/var/opt/microsoft/omsagent/log/kubernetes_perf_log.txt"
            @Log = Logger.new(@LogPath, 'weekly')
    
            def initialize
            end
    
            class << self
                def getSummaryStatsFromCAdvisor()
                    headers = {}
                    response = nil
                    @Log.info 'Getting CAdvisor Uri'
                    begin
                        cAdvisorUri = getCAdvisorUri()
                        if !cAdvisorUri.nil?
                            uri = URI.parse(cAdvisorUri)
                            http = Net::HTTP.new(uri.host, uri.port)
                            http.use_ssl = false
                                
                            cAdvisorApiRequest = Net::HTTP::Get.new(uri.request_uri)
                            response = http.request(cAdvisorApiRequest)
                            @Log.info "Got response code #{response.code} from #{uri.request_uri}"
                        end
                    rescue => error
                        @Log.warn("CAdvisor api request failed: #{error}")
                    end
                    return response
                end
    
                def getCAdvisorUri()
                    begin
                        defaultHost = "http://localhost:10255"
                        relativeUri = "/stats/summary"
                        nodeIP = ENV['NODE_IP']
                        if !nodeIP.nil?
                            @Log.info("Using #{nodeIP + relativeUri} for CAdvisor Uri")
                            return "http://#{nodeIP}:10255" + relativeUri
                        else
                            @Log.warn ("NODE_IP environment variable not set. Using default as : #{defaultHost + relativeUri} ")
                            return defaultHost + relativeUri
                        end
                    end
                end
    
                def getMetrics()
                    metricDataItems = []
                    begin
                        hostName = (OMS::Common.get_hostname)
                        metricInfo = JSON.parse(getSummaryStatsFromCAdvisor().body)
                        metricDataItems.concat(getContainerCpuMetricItems(metricInfo, hostName, "usageNanoCores","cpuUsageNanoCores"))
                        metricDataItems.concat(getContainerMemoryMetricItems(metricInfo, hostName, "usageBytes", "memoryUsageBytes"))

                        metricDataItems.push(getNodeMetricItem(metricInfo, hostName, "cpu", "usageNanoCores", "cpuUsageNanoCores"))
                        metricDataItems.push(getNodeMetricItem(metricInfo, hostName, "memory", "usageBytes", "memoryUsageBytes"))
                        metricDataItems.push(getNodeMetricItem(metricInfo, hostName, "network", "rxBytes", "networkRxBytes"))
                        metricDataItems.push(getNodeMetricItem(metricInfo, hostName, "network", "txBytes", "networkTxBytes"))
                        
                        rescue => error
                        @Log.warn("getContainerMetrics failed: #{error}")
                        return metricDataItems
                    end
                    return metricDataItems
                end

                def getContainerCpuMetricItems(metricJSON, hostName, cpuMetricNameToCollect, metricNametoReturn)
                    metricItems = []
                    begin
                        metricInfo = metricJSON
                        metricInfo['pods'].each do |pod|
                            podUid = pod['podRef']['uid']
                            pod['containers'].each do |container|
                                #cpu metric
                                containerName = container['name']
                                metricValue = container['cpu'][cpuMetricNameToCollect]
                                metricTime = container['cpu']['time']
                                metricItem = {}
                                metricItem['DataItems'] = []
                                
                                metricProps = {}
                                metricProps['Timestamp'] = metricTime
                                metricProps['Host'] = hostName
                                metricProps['ObjectName'] = "K8SContainer"
                                metricProps['InstanceName'] = podUid + "/" + containerName
                                
                                metricProps['Collections'] = []
                                metricCollections = {}
                                metricCollections['CounterName'] = metricNametoReturn
                                metricCollections['Value'] = metricValue

                                metricProps['Collections'].push(metricCollections)
                                metricItem['DataItems'].push(metricProps)
                                metricItems.push(metricItem)
                            end
                        end
                        rescue => error
                        @Log.warn("getcontainerCpuMetricItems failed: #{error} for metric #{cpuMetricNameToCollect}")
                        return metricItems
                    end
                    return metricItems                       
                end

                def getContainerMemoryMetricItems(metricJSON, hostName, memoryMetricNameToCollect, metricNametoReturn)
                    metricItems = []
                    begin
                        metricInfo = metricJSON
                        metricInfo['pods'].each do |pod|
                            podUid = pod['podRef']['uid']
                            pod['containers'].each do |container|
                                containerName = container['name']
                                metricValue = container['memory'][memoryMetricNameToCollect]
                                metricTime = container['memory']['time']
                                
                                metricItem = {}
                                metricItem['DataItems'] = []
                                
                                metricProps = {}
                                metricProps['Timestamp'] = metricTime
                                metricProps['Host'] = hostName
                                metricProps['ObjectName'] = "K8SContainer"
                                metricProps['InstanceName'] = podUid + "/" + containerName
                                
                                metricProps['Collections'] = []
                                metricCollections = {}
                                metricCollections['CounterName'] = metricNametoReturn
                                metricCollections['Value'] = metricValue

                                metricProps['Collections'].push(metricCollections)
                                metricItem['DataItems'].push(metricProps)
                                metricItems.push(metricItem)
                            end
                        end
                        rescue => error
                        @Log.warn("getcontainerMemoryMetricItems failed: #{error} for metric #{memoryMetricNameToCollect}")
                        return metricItems
                    end
                    return metricItems                      
                end

                def getNodeMetricItem(metricJSON, hostName, metricCategory, metricNameToCollect, metricNametoReturn)
                    metricItem = {}
                    begin
                        metricInfo = metricJSON
                        node = metricInfo['node']
                        nodeName = node['nodeName']
                        
                        
                        metricValue = node[metricCategory][metricNameToCollect]
                        metricTime = node[metricCategory]['time']
                        
                        metricItem['DataItems'] = []
                        
                        metricProps = {}
                        metricProps['Timestamp'] = metricTime
                        metricProps['Host'] = hostName
                        metricProps['ObjectName'] = "K8SNode"
                        metricProps['InstanceName'] = nodeName
                        
                        metricProps['Collections'] = []
                        metricCollections = {}
                        metricCollections['CounterName'] = metricNametoReturn
                        metricCollections['Value'] = metricValue

                        metricProps['Collections'].push(metricCollections)
                        metricItem['DataItems'].push(metricProps)
                        
                        rescue => error
                        @Log.warn("getNodeMetricItem failed: #{error} for metric #{metricNameToCollect}")
                        return metricItem
                    end
                    return metricItem                      
                end

            end
        end
