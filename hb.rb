#!/usr/bin/ruby

require 'logger'
require './lib/hb_lib.rb'
include HandbrakeCLI

def cleanup()
  HandbrakeCLI::logger.close()
end

at_exit do

end

Signal.trap("INT") do
  puts "CTRL-C detected - exiting #{File.basename($0)}"
  cleanup()
  exit!(1)
end

options = HandbrakeCLI::HBOptions::parseArgs(ARGV)

# initialize logger
log_device = nil
if options.logfile.nil?
  log_device = Tools::Loggers::DefaultLogDev.new(STDOUT)
else
  log_device = Tools::Loggers::DefaultLogDev.new(STDOUT, File.open(options.logfile, options.logOverride ? "w" : "a"))
end
HandbrakeCLI::logger = Tools::Loggers.createLogger(nil, log_device)
if options.verbose and options.debug
  HandbrakeCLI::logger.level = Logger::DEBUG
elsif options.verbose or options.debug
  HandbrakeCLI::logger.level = Logger::INFO
else
  HandbrakeCLI::logger.level = Logger::WARN
end 

titleMatcher = PosMatcher.new(options.titles)
audioMatcher = LangMatcher.new(options.languages)
audioMatcher.onlyFirstPerAllowedValue = options.onlyFirstTrackPerLanguage
audioMatcher.skipCommentaries = options.skipCommentaries
subtitleMatcher = LangMatcher.new(options.subtitles)
subtitleMatcher.skipCommentaries = options.skipCommentaries

# collect all inputs
inputs = [options.input]
inputs += ARGV if not ARGV.empty?

inout = []
current_loop = options.loops
while current_loop != 0
  inputs.each do |input|
    input = File.expand_path(input)
    if input.include?("*")
      i_list = Dir[input]
      if i_list.empty?
        puts "found no files for pattern #{input}"
        sleep 1
        next
      end
    else
      i_list = [input]
    end
    i_list.each do |i|
      opts = options.dup
      opts.input = i
      unless Tools::FileTool::waitfor(opts.input, options.waitTimeout, "waiting for #{opts.input}...")
        puts "#{opts.input} does not exist"
        next
      end
      results = Handbrake::convert(opts, titleMatcher, audioMatcher, subtitleMatcher)
      inout << [opts.input, results.collect{|r| r.file}]
    end
  end
  current_loop -= 1
end

# default overview
HandbrakeCLI::logger.warn("overview")
inout.each do |input,outputs|
  HandbrakeCLI::logger.warn("#{input}")
  if outputs.empty?
    HandbrakeCLI::logger.warn("  -> n/a")
  else
    outputs.each{|file| HandbrakeCLI::logger.warn("  -> #{file}") }
  end
end

# additional overview-file
unless options.logOverview.nil?
  File.open(options.logOverview, options.logOverride ? "w" : "a"){ |file|
    file.puts "overview"
    inout.each do |input, outputs|
      file.puts input
      if outputs.empty?
        file.puts "  --> n/a"
      else
        outputs.each {|o| file.puts "  --> #{o}" }
      end
    end
  }
end