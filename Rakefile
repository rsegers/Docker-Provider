require "rake/testtask"

task default: "test"

Rake::TestTask.new do |task|
  task.libs << "test"
  task.pattern = "./test/unit-tests/plugins/health/*_spec.rb"
  task.warning = false
end
