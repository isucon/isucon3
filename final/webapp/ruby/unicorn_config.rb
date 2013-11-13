worker_processes 10
preload_app true

after_fork do |server, worker|
  UUID.generator.next_sequence
end
