require_relative '../test_helpers'
# consider doing this in test_helpers.rb so that this code is common
Dir[File.join(File.expand_path(File.dirname(__FILE__)), "../../../../source/plugins/ruby/health/*.rb")].reject{|f| f.include?('health_monitor_utils')}.each { |file| require file }
include HealthModel
include Minitest

describe "HealthModelBuilder spec" do
    it "Verify hierarchy builder and finalizer public methods are called" do
        #arrange
        mock_hierarchy_builder = Mock::new
        health_record = Mock::new
        mock_monitor_set = Mock::new
        mock_state_finalizer = Mock::new
        mock_hierarchy_builder.expect(:process_record, nil,  [health_record, mock_monitor_set])
        mock_state_finalizer.expect(:finalize, {}, [mock_monitor_set])
        def mock_monitor_set.get_map; {}; end

        #act
        builder = HealthModelBuilder.new(mock_hierarchy_builder, [mock_state_finalizer], mock_monitor_set)
        builder.process_records([health_record])
        builder.finalize_model
        #assert
        assert mock_hierarchy_builder.verify
        assert mock_state_finalizer.verify
    end

    it "Verify finalize_model raises if state_finalizers is empty" do
        #arrange
        mock_hierarchy_builder = Mock.new
        mock_monitor_set = Mock.new
        builder = HealthModelBuilder.new(mock_hierarchy_builder, [], mock_monitor_set)
        #act and assert
        assert_raises do
            builder.finalize_model
        end
    end
end