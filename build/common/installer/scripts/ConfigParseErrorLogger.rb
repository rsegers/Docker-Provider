#!/usr/local/bin/ruby
# frozen_string_literal: true

class ConfigParseErrorLogger
  require "json"

  def initialize
  end

  class << self
    def logError(message)
      begin
        errorMessage = "config::error::" + message
        jsonMessage = errorMessage.to_json
        STDERR.puts "\e[31m" + jsonMessage + "\e[0m" #Using red color for error messages
      rescue => errorStr
        puts "Error in ConfigParserErrorLogger::logError: #{errorStr}"
      end
    end
  end
end
