require_relative '../test_helpers'
# consider doing this in test_helpers.rb so that this code is common
Dir[File.join(File.expand_path(File.dirname(__FILE__)), "../../../../source/code/plugin/health/*.rb")].reject{|f| f.include?('health_monitor_utils')}.each { |file| require file }
include HealthModel

describe "HealthModelDefinitionParser spec " do
    it "parses the definition file correctly with the right conditions" do
        #arrange

        parser = HealthModelDefinitionParser.new(File.join(File.expand_path(File.dirname(__FILE__)), 'test_health_model_definition.json'))
        #act
        model_definition = parser.parse_file

        #assert
        assert_equal model_definition['conditional_monitor_id'].key?("conditions"), true
        assert_equal model_definition['conditional_monitor_id']["conditions"].size, 2
        assert_equal model_definition['conditional_monitor_id'].key?("parent_monitor_id"), false

        #assert
        assert_equal model_definition['monitor_id'].key?("conditions"), false
        assert_equal model_definition['monitor_id'].key?("parent_monitor_id"), true
    end

end