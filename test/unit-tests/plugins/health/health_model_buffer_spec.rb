require_relative '../../../../source/plugins/ruby/health/health_model_buffer'
require_relative '../test_helpers'

include HealthModel

describe "HealthModelBuffer Spec" do
    it "get_buffer returns the correct buffer data" do
        # Arrange
        buffer = HealthModelBuffer.new
        # Act
        buffer.add_to_buffer(['mockRecord'])
        # Assert
        assert_equal buffer.get_buffer.length, 1

        #Act
        buffer.add_to_buffer(['mockRecord1', 'mockRecord2'])
        #Assert
        assert_equal buffer.get_buffer.length, 3

        #Act
        buffer.reset_buffer
        #Assert
        assert_equal buffer.get_buffer.length, 0
    end
end