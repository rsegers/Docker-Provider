module HealthModel

=begin
    Class that is used to create a buffer for collecting the health records
=end
    class HealthModelBuffer

        attr_reader :records_buffer, :log

        def initialize
            @records_buffer = []
        end

        # Returns the current buffer
        def get_buffer
            return @records_buffer
        end

        # adds records to the buffer
        def add_to_buffer(records)
            @records_buffer.push(*records)
        end

        # clears/resets the buffer
        def reset_buffer
            @records_buffer = []
        end
    end
end