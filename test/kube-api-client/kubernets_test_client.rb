require "json"
require "logger"
require "net/http"
require "net/https"
require "uri"
require "time"
require "ipaddress"

CaFile = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
TokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token"

APIEndpoint = "https://#{ENV["KUBERNETES_SERVICE_HOST"]}:#{ENV["KUBERNETES_PORT_443_TCP_PORT"]}/api/v1/pods?limit=50"

token = File.read(TokenFile).strip
uri = URI.parse(APIEndpoint)
Net::HTTP.start(uri.host, uri.port, :use_ssl => true, :ca_file => CaFile, :verify_mode => OpenSSL::SSL::VERIFY_PEER, :open_timeout => 20, :read_timeout => 40) do |http|
  kubeApiRequest = Net::HTTP::Get.new(uri.request_uri)
  kubeApiRequest["Authorization"] = "Bearer " + token
  response = http.request(kubeApiRequest)
  puts "KubernetesAPIClient::getKubeResourceInfo : Got response of #{response.code} for #{uri.request_uri} @ #{Time.now.utc.iso8601}"
end
