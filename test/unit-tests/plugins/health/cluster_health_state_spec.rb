require_relative '../test_helpers'
Dir[File.join(File.expand_path(File.dirname(__FILE__)), "../../../../source/plugins/ruby/health/*.rb")].reject{|f| f.include?('health_monitor_utils')}.each { |file| require file }
require 'time'
include HealthModel
include Minitest

describe "Cluster Health State Spec" do

    it "ClusterHealthState.new throws if cert file is NOT present" do
        state = {
            "m1" => {
                "state" => "pass",
                "time"  => Time.now.utc.iso8601
            }
        }

        token_file_path = 'token'
        cert_file_path = '/var/ca.crt'

        proc {ClusterHealthState.new(token_file_path, cert_file_path)}.must_raise

    end

    it "ClusterHealthState.new returns nil if token is NOT present" do
        state = {
            "m1" => {
                "state" => "pass",
                "time"  => Time.now.utc.iso8601
            }
        }
        token_file_path = 'token'
        cert_file_path = File.join(File.expand_path(File.dirname(__FILE__)), "ca.crt")

        chs = ClusterHealthState.new(token_file_path, cert_file_path)
        chs.token.must_be_nil
    end
end
