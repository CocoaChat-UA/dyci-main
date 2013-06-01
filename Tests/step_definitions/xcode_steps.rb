require "xcode_build"
require "bundler"
require 'timeout'
require 'pty'
require 'open3'

require File.expand_path('../../support/xcode_steps_helper', __FILE__)
require File.expand_path('../../support/helpers', __FILE__)

def d_puts(s)
  puts s if @debug_mode == true
end


Before do |scenario|
  @debug_mode = false
  @config = XcodeTestsHelper.new if @config == nil
  d_puts "Before scenario: #{scenario.title}"

  #Configurable parameters for some
  @test_project_path = "tmp/project-dir"

  #output that generated with feature
  @feature_debug_output = "/tmp/ruby-output2"

  #output that generated by running application
  @application_output = "/tmp/ruby-output"

  #compilation / build output. Will be visible on debug
  @build_debug_output = "/tmp/build.output"

  #file that held output that was read from application output :))
  @feature_read_output = "/tmp/ruby-read-output"

  #prepare all outputs
  FileUtils.rm_r(@feature_debug_output) if File.exist? @feature_debug_output
  FileUtils.rm_r(@application_output) if File.exist? @application_output
  FileUtils.rm_r(@build_debug_output) if File.exist? @build_debug_output
  FileUtils.rm_r(@feature_read_output) if File.exist? @feature_read_output

end


When /^project was successfully built$/ do

  @source_project_path = "fixtures/#{@config.fixtures_project_dir}"

  fail "Cannot start without project name" if @config.project_name == nil

  d_puts "Copying #@source_project_path to #@test_project_path"
  FileUtils.rm_r(@test_project_path) if File.exist? @test_project_path
  FileUtils.mkdir_p(@test_project_path)
  FileUtils.cp_r(@source_project_path, @test_project_path, :remove_destination => true)
  @config.test_project_root = @test_project_path
  @config.test_project_sources_root = File.join(@test_project_path, File.basename(@source_project_path)).to_s


  # Setting up build dir
  project_output_path = @config.output_dir
  d_puts "Setting up output directory to #{project_output_path}"
  FileUtils.rm_r(project_output_path) if File.exists? project_output_path
  @config.output_dir = project_output_path


  # Building project
  d_puts "output dir is #{@config.output_dir} and test project root is #{@config.test_project_root} and pr path is #{@config.test_project_sources_root}"
  d_puts "Project name is #{@config.project_name}"


  # Xcconfig file for little more configuration
  xcconfig_location = "/tmp/config.xcconfig"
  write_file(xcconfig_location,
             "" "
    OBJROOT=#{@config.output_dir}
    SYMROOT=#{@config.output_dir}
    OTHER_CFLAGS= -DCEDAR_KNOWS_SOMETHING_ABOUT_FAILING_ON_IOS6_SIMULATOR=1
    " ""
  )

  # Running this on via fork, because...
  # Because sometimes..
  @build_project_process = fork do

    File.open(@feature_debug_output, 'w') { |f| f.puts "output dir is #{@config.output_dir} and test project root is #{@config.test_project_root} and pr path is #{@config.test_project_sources_root}" }

    task_working_dir = File.join(@config.test_project_root, @config.fixtures_project_dir)
    d_puts "Running at '#{task_working_dir}"
    File.open(@feature_debug_output, 'a') { |f| f.puts "Running at '#{task_working_dir}" }


    task = XcodeBuild::Tasks::BuildTask.new do |t|
      t.scheme = @config.scheme_name
      t.workspace = @config.workspace_name
      t.invoke_from_within = task_working_dir
      t.sdk = "iphonesimulator#{@config.sdk_version}"
      t.configuration = @config.configuration
      t.output_to = @build_debug_output unless @debug_mode
      t.xcconfig = xcconfig_location
    end

    d_puts "Build opts #{task.build_opts}"
    File.open(@feature_debug_output, 'a') { |f| f.puts "Build opts #{task.build_opts}" }

    task.run("clean")
    task.run("build")
  end

  d_puts "Waiting for project build"
  Process.wait(@build_project_process)
end


#Config setup
Given /^output directory setup to `([^`]*)`$/ do |output_dir|
  @config.output_dir = output_dir
end

When /^project from `([^`]*)` with  name `([^`]*)` is used$/ do |fixtures_project_dir, project_name|
  @config.fixtures_project_dir = fixtures_project_dir
  @config.project_name = project_name

  d_puts "Setting up @config.fixtures_project_dir = #{@config.fixtures_project_dir}"
  d_puts "Setting up @config.project_name = #{@config.project_name}"

  #Kill previous instance of
  kill_process_with_name(@config.project_name)

end

When /^project build is configured to `([^`]*)` workspace and `([^`]*)` scheme$/ do |workspace_name, scheme_name|
  @config.workspace_name = workspace_name
  @config.scheme_name = scheme_name
end


def run_project(app_name)
  #puts "Project started to run"
  d_puts "Killing previous running instance"
  %x[kill -9 #{app_name} > /dev/null 2>&1]
  sleep(1)
  env_vars = {
      "DYLD_ROOT_PATH" => @config.sdk_dir,
      "IPHONE_SIMULATOR_ROOT" => @config.sdk_dir,
      "CFFIXED_USER_HOME" => Dir.tmpdir,
      "DYLD_FALLBACK_LIBRARY_PATH" => @config.sdk_dir,
  }

  project_file = File.join(@config.build_dir("-iphonesimulator"), "#{app_name}.app", app_name)
  unless File.exist? project_file
    fail "No file to run #{project_file}. It seems that build was failed"
  end

  run_project_command = "#{project_file} -RegisterForSystemEvents > #@application_output 2>&1"

  with_env_vars(env_vars) do

    Open3.popen3("#{run_project_command}")

  end

  d_puts "Forked project to run"

end

#=========================================================


# Steps

Given /^I start project$/ do
  d_puts "Starting project #{@config.project_name}"
  run_project(@config.project_name)
end


When /^I end project process$/ do
  kill_process_with_name(@config.project_name)
end


When /^Change its source file "([^"]*)" with contents of file "([^"]*)"$/ do |des_file, source_file|
  FileUtils.cp(File.join(@config.test_project_sources_root, source_file), File.join(@config.test_project_sources_root, des_file))
end


When /^Inject inject new version of "([^"]*)" with "([^"]*)" as test string$/ do |file_path, value|
  d_puts "#{Time.now} : Waiting 1 sec to project started"
  sleep(1)

  #Replacing file
  file = File.expand_path(File.join(@config.test_project_sources_root, file_path).to_s)
  text = File.read(file.to_s)
  replace = text.gsub(/######/, value)
  File.open(file.to_s, "w") { |f| f.puts replace }

  d_puts "#{Time.now} : Starting injection"

  verbose_recompile = "> /tmp/ruby-output-dyci-recompilation 2>&1"
  verbose_recompile = "> /dev/null 2>&1" if @debug_mode == false
  system("~/.dyci/scripts/dyci-recompile.py #{file} #{verbose_recompile}")
  result_code = $?.exitstatus
  unless result_code == 0
    fail("Unable to inject source python file failed")
  end

  d_puts "Injection result code is #{result_code}"
end


Then /^I should see "([^"]*)" in running project output$/ do |arg|
  d_puts "Checking project output"
  begin
    Timeout.timeout(5) do
      expect_string_found = false
      until expect_string_found do
        sleep 0.1
        File.open('/tmp/ruby-output', 'r') do |f1|
          File.open(@feature_read_output, 'w') {|f| f.write('Starting') }
          f1.readlines.each { |line|
            File.open(@feature_read_output, 'a') {|f| f.write(line) }
            if line.include? arg
              expect_string_found = true
              break
            end
          }
        end
      end
    end
  rescue Timeout::Error
    fail("There is no #{arg} in project output :(")
  end
end

## Helpers --
def kill_process_with_name(project_name)
  # code here
  pid = `ps -eo pid,comm | awk '/#{project_name}$/  {print $1; exit}'`
  system("kill -9 #{pid}") unless pid
end
