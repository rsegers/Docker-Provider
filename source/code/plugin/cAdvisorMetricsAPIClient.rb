#!/usr/local/bin/ruby

class CAdvisorMetricsApiClient
    
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
                        if !nodeIP.nil
                            @Log.info("Using #{nodeIP + relativeUri} for CAdvisor Uri")
                            return "http://#{ENV['NODE_IP']}:10255" + relativeUri
                        else
                            @Log.warn ("NODE_IP environment variable not set. Using default as : #{defaultHost + relativeUri} ")
                            return defaultHost + relativeUri
                        end
                    end
                end
    
                def getMetrics()
                    metricDataItems = []
                    begin
                        metricInfo = JSON.parse(getSummaryStatsFromCAdvisor().body)
                        metricInfo['pods'].each do |pod|
                            podUid = pod['podRef']['uid']
                            pod['containers'].each do |container|
                                containerName = container['name']
                                cpuUsageNanoCores = container['cpu']['usageNanoCores']
                                metrictime = container['cpu']['time']
                                metricItem = 
                                    DataItems : {
                                        Host : (OMS::Common.get_hostname)
                                        Timestamp : metrictime,
                                        ObjectName : "K8SContainer",
                                        InstanceName : podUid + "/" + containerName,
                                        Collections : {
                                            CounterName : "cpuUsageNanoCores"
                                            Value : cpuUsageNanoCores
                                        }
                                    }
                                metricDataItems.push(metricItem)
                            end
                        end
                        rescue => error
                        @Log.warn("getMetrics failed: #{error}")
                        return []
                    end
                    return metricDataItems
                end
            end
        end