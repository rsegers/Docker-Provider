require_relative '../test_helpers'
Dir[File.join(File.expand_path(File.dirname(__FILE__)), "../../../../source/plugins/ruby/health/*.rb")].reject{|f| f.include?('health_monitor_utils')}.each { |file| require file }
include HealthModel

describe "KubeApiDownHandler spec" do
    it "updates states for monitors in monitors_to_change" do
        #arrange
        record1 = HealthMonitorRecord.new("node_condition", "node_condition-node1", Time.now.utc.iso8601, "pass", {}, {}, {})
        record2 = HealthMonitorRecord.new("kube_api_status", "kube_api_status", Time.now.utc.iso8601, "fail", {}, {}, {})
        record3 = HealthMonitorRecord.new("user_workload_pods_ready", "user_workload_pods_ready-workload1", Time.now.utc.iso8601, "pass", {}, {}, {})
        record4 = HealthMonitorRecord.new("system_workload_pods_ready", "system_workload_pods_ready-workload2", Time.now.utc.iso8601, "pass", {}, {}, {})
        record5 = HealthMonitorRecord.new("subscribed_capacity_cpu", "subscribed_capacity_cpu", Time.now.utc.iso8601, "pass", {}, {}, {})
        record6 = HealthMonitorRecord.new("subscribed_capacity_memory", "subscribed_capacity_memory", Time.now.utc.iso8601, "pass", {}, {}, {})
        handler = HealthKubeApiDownHandler.new

        #act
        handler.handle_kube_api_down([record1, record2, record3, record4, record5, record6])
        #assert
        assert_equal record1.state, HealthMonitorStates::UNKNOWN
        assert_equal record3.state, HealthMonitorStates::UNKNOWN
        assert_equal record4.state, HealthMonitorStates::UNKNOWN
        assert_equal record5.state, HealthMonitorStates::UNKNOWN
        assert_equal record6.state, HealthMonitorStates::UNKNOWN

    end
end
