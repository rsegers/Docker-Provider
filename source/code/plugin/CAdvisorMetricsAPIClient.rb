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
                        metricDataItems.push(getContainerCpuMetricItem(metricInfo, hostName, "usageNanoCores","cpuUsageNanoCores"))
                        metricDataItems.push(getContainerMemoryMetricItem(metricInfo, hostName, "usageBytes", "memoryUsageBytes"))
                        rescue => error
                        @Log.warn("getContainerMetrics failed: #{error}")
                        return metricDataItems
                    end
                    return metricDataItems
                end

                def getContainerCpuMetricItem(metricJSON, hostName, cpuMetricNameToCollect, metricNametoReturn)
                    metricItem = {}
                    begin
                        metricInfo = metricJSON
                        metricInfo['pods'].each do |pod|
                            podUid = pod['podRef']['uid']
                            pod['containers'].each do |container|
                                #cpu metric
                                containerName = container['name']
                                metricValue = container['cpu'][cpuMetricNameToCollect]
                                metricTime = container['cpu']['time']
                                
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
                            end
                        end
                        rescue => error
                        @Log.warn("getcontainerCpuMetrics failed: #{error} for metric #{cpuMetricNameToCollect}")
                        return metricItem
                    end
                    return metricItem                       
                end

                def getContainerMemoryMetricItem(metricJSON, hostName, memoryMetricNameToCollect, metricNametoReturn)
                    metricItem = {}
                    begin
                        metricInfo = metricJSON
                        metricInfo['pods'].each do |pod|
                            podUid = pod['podRef']['uid']
                            pod['containers'].each do |container|
                                containerName = container['name']
                                metricValue = container['memory'][memoryMetricNameToCollect]
                                metricTime = container['memory']['time']
                                
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
                            end
                        end
                        rescue => error
                        @Log.warn("getcontainerMemoryMetrics failed: #{error} for metric #{memoryMetricNameToCollect}")
                        return metricItem
                    end
                    return metricItem                       
                end

            end
        end
