require_relative '../test_helpers'
# consider doing this in test_helpers.rb so that this code is common
Dir[File.join(File.expand_path(File.dirname(__FILE__)), "../../../../source/code/plugin/health/*.rb")].reject{|f| f.include?('health_monitor_utils')}.each { |file| require file }
include HealthModel
include Minitest

describe "HealthSignalReducer spec" do
    it "returns the right set of records -- no reduction" do
        #arrange
        record1 = Mock.new
        def record1.monitor_id; "node_cpu_utilization"; end
        def record1.monitor_instance_id; "node_cpu_utilization-node1"; end
        def record1.labels; {HealthMonitorLabels::HOSTNAME => "node1"}; end
        inventory = Mock.new
        def inventory.get_nodes; ["node1"]; end
        def inventory.get_workload_names; []; end
        reducer = HealthSignalReducer.new
        #act
        reduced = reducer.reduce_signals([record1], inventory)
        #Assert
        assert_equal reduced.size, 1
    end

    it "returns only the latest record if multiple records are present for the same monitor" do
        #arrange
        record1 = Mock.new
        def record1.monitor_id; "node_cpu_utilization"; end
        def record1.monitor_instance_id; "node_cpu_utilization-node1"; end
        def record1.labels; {HealthMonitorLabels::HOSTNAME => "node1"}; end
        def record1.transition_date_time; Time.now.utc.iso8601 ; end


        record2 = Mock.new
        def record2.monitor_id; "node_cpu_utilization"; end
        def record2.monitor_instance_id; "node_cpu_utilization-node1"; end
        def record2.labels; {HealthMonitorLabels::HOSTNAME => "node1"}; end
        def record2.transition_date_time; "#{Time.now.utc.iso8601}"  ; end

        inventory = Mock.new
        def inventory.get_nodes; ["node1"]; end
        def inventory.get_workload_names; []; end
        reducer = HealthSignalReducer.new
        #act
        reduced = reducer.reduce_signals([record1, record2], inventory)
        #Assert
        assert_equal reduced.size, 1
    end

    it "returns only those records if the node is present in the inventory" do
        #arrange
        record1 = Mock.new
        def record1.monitor_id; "node_cpu_utilization"; end
        def record1.monitor_instance_id; "node_cpu_utilization-node1"; end
        def record1.labels; {HealthMonitorLabels::HOSTNAME => "node1"}; end
        inventory = Mock.new
        def inventory.get_nodes; ["node2"]; end
        def inventory.get_workload_names; []; end

        #act
        reducer = HealthSignalReducer.new
        #assert
        assert_equal reducer.reduce_signals([record1], inventory).size, 0
    end

    it "returns only those records if the workdload name is present in the inventory" do
        #arrange
        record1 = Mock.new
        def record1.monitor_id; "user_workload_pods_ready"; end
        def record1.monitor_instance_id; "user_workload_pods_ready-workload1"; end
        def record1.labels; {HealthMonitorLabels::NAMESPACE => "default", HealthMonitorLabels::WORKLOAD_NAME => "workload1"}; end
        def record1.transition_date_time; Time.now.utc.iso8601 ; end

        inventory = Mock.new
        def inventory.get_nodes; ["node2"]; end
        def inventory.get_workload_names; ["default~~workload1"]; end
        reducer = HealthSignalReducer.new

        #act
        reduced = reducer.reduce_signals([record1], inventory)

        #assert
        assert_equal reduced.size, 1

        #arrange
        record2 = Mock.new
        def record2.monitor_id; "user_workload_pods_ready"; end
        def record2.monitor_instance_id; "user_workload_pods_ready-workload2"; end
        def record2.labels; {HealthMonitorLabels::NAMESPACE => "default1", HealthMonitorLabels::WORKLOAD_NAME => "workload2"}; end
        def record1.transition_date_time; Time.now.utc.iso8601 ; end
        #act
        reduced = reducer.reduce_signals([record1, record2], inventory)
        #assert
        assert_equal reduced.size, 1
    end

end
