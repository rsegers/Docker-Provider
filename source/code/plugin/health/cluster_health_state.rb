require "net/http"
require "net/https"
require "uri"

module HealthModel
    class ClusterHealthState

        attr_reader :token_file_path, :cert_file_path, :log, :http_client, :uri, :token
        @@resource_uri_template = "%{kube_api_server_url}/apis/azmon.container.insights/v1/namespaces/kube-system/healthstates/cluster-health-state"

        def initialize(token_file_path, cert_file_path)
            @token_file_path = token_file_path
            @cert_file_path = cert_file_path
            @log = HealthMonitorHelpers.get_log_handle
            @http_client = get_http_client
            @token = get_token
        end

        def update_state(state) #state = hash of monitor_instance_id to HealthMonitorInstanceState struct
            get_request = Net::HTTP::Get.new(@uri.request_uri)
            monitor_states_hash = {}
            state.each {|monitor_instance_id, health_monitor_instance_state|
                monitor_states_hash[monitor_instance_id] = health_monitor_instance_state.to_h
            }

            get_request["Authorization"] = "Bearer #{@token}"
            @log.info "Making GET request to #{@uri.request_uri} @ #{Time.now.utc.iso8601}"
            get_response = @http_client.request(get_request)
            @log.info  "Got response of #{get_response.code} for #{@uri.request_uri} @ #{Time.now.utc.iso8601}"

            if get_response.code.to_i == 404 # NOT found
                #POST
                update_request = Net::HTTP::Post.new(@uri.request_uri)
                update_request["Content-Type"] = "application/json"

            elsif get_response.code.to_i == 200 # Update == Patch
                #PATCH
                update_request = Net::HTTP::Patch.new(@uri.request_uri)
                update_request["Content-Type"] = "application/merge-patch+json"
            end
            update_request["Authorization"] = "Bearer #{@token}"

            update_request_body = get_update_request_body
            update_request_body["state"] = monitor_states_hash.to_json
            update_request.body = update_request_body.to_json

            update_response = @http_client.request(update_request)
            @log.info "Got a response of #{update_response.code} for #{update_request.method}"
        end

        def get_state
            get_request = Net::HTTP::Get.new(@uri.request_uri)
            get_request["Authorization"] = "Bearer #{@token}"
            @log.info "Making GET request to #{@uri.request_uri} @ #{Time.now.utc.iso8601}"
            get_response = @http_client.request(get_request)
            @log.info  "Got response of #{get_response.code} for #{@uri.request_uri} @ #{Time.now.utc.iso8601}"

            if get_response.code.to_i == 200
                return JSON.parse(JSON.parse(get_response.body)["state"])
            else
                return {}
            end
        end

        private
        def get_token()
            begin
              if File.exist?(@token_file_path) && File.readable?(@token_file_path)
                token_str = File.read(@token_file_path).strip
                return token_str
              else
                @log.info ("Unable to read token string from #{@token_file_path}")
                return nil
              end
            end
        end

        def get_http_client()
            kube_api_server_url = get_kube_api_server_url
            resource_uri = @@resource_uri_template % {
                kube_api_server_url: kube_api_server_url
            }
            @uri = URI.parse(resource_uri)
            http = Net::HTTP.new(@uri.host, @uri.port)
            http.use_ssl = true
            if !File.exist?(@cert_file_path)
              raise "#{@cert_file_path} doesnt exist"
            else
              http.ca_file = @cert_file_path
            end
            http.verify_mode = OpenSSL::SSL::VERIFY_PEER
            return http
        end

        def get_kube_api_server_url
            if ENV["KUBERNETES_SERVICE_HOST"] && ENV["KUBERNETES_PORT_443_TCP_PORT"]
                return "https://#{ENV["KUBERNETES_SERVICE_HOST"]}:#{ENV["KUBERNETES_PORT_443_TCP_PORT"]}"
            else
                @log.warn ("Kubernetes environment variable not set KUBERNETES_SERVICE_HOST: #{ENV["KUBERNETES_SERVICE_HOST"]} KUBERNETES_PORT_443_TCP_PORT: #{ENV["KUBERNETES_PORT_443_TCP_PORT"]}. Unable to form resourceUri")
                if Gem.win_platform? #unit testing on windows dev machine
                    value = %x( kubectl -n default get endpoints kubernetes --no-headers)
                    url = "https://#{value.split(' ')[1]}"
                    return "https://localhost:8080"  # This is NEVER used. this is just to return SOME value
                end
                return nil
            end
        end

        def get_update_request_body
            body = {}
            body["apiVersion"] = "azmon.container.insights/v1"
            body["kind"] = "HealthState"
            body["metadata"] = {}
            body["metadata"]["name"] = "cluster-health-state"
            body["metadata"]["namespace"]  = "kube-system"
            return body
        end
    end
end
