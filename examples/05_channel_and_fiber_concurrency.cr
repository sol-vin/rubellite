require "../src/rubellite"

puts "\e[1;35m=== Rubellite Example 05: Channel & Concurrency Bridge ===\e[0m\n"

Rubellite.start do
  # 1. Create typed Crystal channels
  job_channel = Channel(String).new(5)
  result_channel = Channel(Int64).new(5)

  # 2. Export channels to Ruby
  Rubellite.export_channel("jobs", job_channel)
  Rubellite.export_channel("results", result_channel)

  # 3. Preload the job channel from Crystal
  job_channel.send("Crystal and Ruby pair programming")
  job_channel.send("High performance interop framework")

  # 4. Ruby script receives from job channel, processes, and sends back
  Rubellite.eval(<<-'RUBY')
    task1 = jobs.receive
    results.send(task1.split.size)
    task2 = jobs.receive
    results.send(task2.split.size)
  RUBY

  # 5. Receive processed results in Crystal
  res1 = result_channel.receive
  res2 = result_channel.receive

  puts "Job 1 word count: #{res1}"
  puts "Job 2 word count: #{res2}"
  puts "Concurrency pipeline completed successfully!"
end
