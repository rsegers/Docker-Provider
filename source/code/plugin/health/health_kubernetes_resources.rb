require 'singleton'
require_relative 'health_model_constants'

module HealthModel
    class HealthKubernetesResources

        include Singleton
        attr_accessor :node_inventory, :pod_inventory, :deployment_inventory
        attr_reader :nodes, :pods, :workloads

        def initialize
            @node_inventory = []
            @pod_inventory =  []
            @deployment_inventory =  []
            @nodes = []
            @pods = []
            @workloads = []
            @log = HealthMonitorHelpers.get_log_handle
        end

        def get_node_inventory
            return @node_inventory
        end

        def get_nodes
            @nodes = []
            @node_inventory['items'].each {|node|
                if !@nodes.include?(node['metadata']['name'])
                    @nodes.push(node['metadata']['name'])
                end

            }
            return @nodes
        end

        def get_pod_inventory
            return @pod_inventory
        end

        def get_pods
            return @pods
        end

        def get_workload_names
            @pods = []
            workload_names = {}
            deployment_lookup = {}
            @deployment_inventory['items'].each do |deployment|
                match_labels = deployment['spec']['selector']['matchLabels'].to_h
                namespace = deployment['metadata']['namespace']
                match_labels.each{|k,v|
                    deployment_lookup["#{namespace}-#{k}=#{v}"] = "#{deployment['metadata']['namespace']}~~#{deployment['metadata']['name']}"
                }
            end
            @pod_inventory['items'].each do |pod|
                begin
                    has_owner = !pod['metadata']['ownerReferences'].nil?
                    owner_kind = ''
                    if has_owner
                        owner_kind = pod['metadata']['ownerReferences'][0]['kind']
                        controller_name = pod['metadata']['ownerReferences'][0]['name']
                    else
                        owner_kind = pod['kind']
                        controller_name = pod['metadata']['name']
                    end

                    namespace = pod['metadata']['namespace']

                    workload_name = ''
                    if owner_kind.nil?
                        owner_kind = 'Pod'
                    end
                    case owner_kind.downcase
                    when 'job'
                        # we are excluding jobs
                        next
                    when 'replicaset'
                        # get the labels, and see if there is a match. If there is, it is the deployment. If not, use replica set name/controller name
                        labels = pod['metadata']['labels'].to_h
                        labels.each {|k,v|
                            lookup_key = "#{namespace}-#{k}=#{v}"
                            if deployment_lookup.key?(lookup_key)
                                workload_name = deployment_lookup[lookup_key]
                                break
                            end
                        }
                        if workload_name.empty?
                            workload_name = "#{namespace}~~#{controller_name}"
                        end
                    when 'daemonset'
                        workload_name = "#{namespace}~~#{controller_name}"
                    else
                        workload_name = "#{namespace}~~#{pod['metadata']['name']}"
                    end
                rescue => e
                    @log.info "Error when processing pod #{pod['metadata']['name']} #{e.message}"
                end
                workload_names[workload_name] = true
            end
            return workload_names.keys
        end
    end
end