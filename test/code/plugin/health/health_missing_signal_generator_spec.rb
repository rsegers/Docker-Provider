require_relative '../test_helpers'
Dir[File.join(File.expand_path(File.dirname(__FILE__)), "../../../../source/code/plugin/health/*.rb")].reject{|f| f.include?('health_monitor_utils')}.each {|file| require file}
include HealthModel
include Minitest

describe "HealthMissingSignalGenerator spec" do
    it 'generates missing node signals' do
        #arrange
        resources = Mock.new
        resources.expect(:get_nodes, ["node1"])
        resources.expect(:get_workload_names, ["default~~workload1"])

        provider = Mock.new
        provider.expect(:get_node_labels, {HealthMonitorLabels::HOSTNAME => "node1"}, ["node1"])

        node1_cpu_record = Mock.new
        def node1_cpu_record.monitor_id; "node_cpu_utilization"; end
        def node1_cpu_record.monitor_instance_id; "node_cpu_utilization"; end
        def node1_cpu_record.labels; {HealthMonitorLabels::HOSTNAME => "node1"}; end
        def node1_cpu_record.config; {}; end
        def node1_cpu_record.state; "pass"; end

        node1_memory_record = Mock.new
        def node1_memory_record.monitor_id; "node_memory_utilization"; end
        def node1_memory_record.monitor_instance_id; "node_memory_utilization"; end
        def node1_memory_record.labels; {HealthMonitorLabels::HOSTNAME => "node1"}; end
        def node1_memory_record.config; {}; end
        def node1_memory_record.state; "pass"; end

        node1_condition_record = Mock.new
        def node1_condition_record.monitor_id; "node_condition"; end
        def node1_condition_record.monitor_instance_id; "node_condition-0c593682737a955dc8e0947ad12754fe"; end
        def node1_condition_record.labels; {HealthMonitorLabels::HOSTNAME => "node1"}; end
        def node1_condition_record.config; {}; end
        def node1_condition_record.state; "pass"; end


        workload1_pods_ready_record = Mock.new
        def workload1_pods_ready_record.monitor_id; "user_workload_pods_ready"; end
        def workload1_pods_ready_record.monitor_instance_id; "user_workload_pods_ready-workload1"; end
        def workload1_pods_ready_record.labels; {HealthMonitorLabels::NAMESPACE => "default", HealthMonitorLabels::WORKLOAD_NAME => "workload1"}; end
        def workload1_pods_ready_record.config; {}; end
        def workload1_pods_ready_record.state; "pass"; end

        generator = HealthMissingSignalGenerator.new
        generator.update_last_received_records([node1_cpu_record, node1_memory_record, node1_condition_record, workload1_pods_ready_record])

        #act
        missing = generator.get_missing_signals('fake_cluster_id', [node1_cpu_record, node1_memory_record], resources, provider)

        #assert
        assert_equal missing.size, 2

        assert_equal missing[0].monitor_id, "node_condition"
        assert_equal missing[0].state, "unknown"
        assert_equal missing[0].monitor_instance_id, "node_condition-0c593682737a955dc8e0947ad12754fe"

        assert_equal missing[1].monitor_id, "user_workload_pods_ready"
        assert_equal missing[1].state, "unknown"
        assert_equal missing[1].monitor_instance_id, "user_workload_pods_ready-workload1"

        #arrange
        resources.expect(:get_nodes, ["node1"])
        resources.expect(:get_workload_names, ["default~~workload1"])
        provider.expect(:get_node_labels, {HealthMonitorLabels::HOSTNAME => "node1"}, ["node1"])
        generator.update_last_received_records([node1_cpu_record, node1_memory_record])
        #act
        missing = generator.get_missing_signals('fake_cluster_id', [node1_cpu_record, node1_memory_record], resources, provider)
        #assert
        assert_equal missing.size, 2
        assert_equal missing[0].monitor_id, "node_condition"
        assert_equal missing[0].state, "unknown"
        assert_equal missing[0].monitor_instance_id, "node_condition-0c593682737a955dc8e0947ad12754fe"

        assert_equal missing[1].monitor_id, "user_workload_pods_ready"
        assert_equal missing[1].state, "none"
        assert_equal missing[1].monitor_instance_id, "user_workload_pods_ready-workload1"
    end
end