#!/usr/bin/env ruby

require 'logger'
require File.join(File.dirname(File.absolute_path(__FILE__)), "lib", "hb_lib.rb")
include HandbrakeCLI

puts "#{File.basename($0)} Copyright (C) 2014 AlBundy
This program comes with ABSOLUTELY NO WARRANTY; for details see LICENSE.txt.
This is free software, and you are welcome to redistribute it under certain conditions.

For questions, feature-requests etc. visit: https://forum.handbrake.fr/viewtopic.php?f=10&t=26163

"
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
subtitleMatcher.skipForced = options.skipForced

# collect all inputs
inputs = [options.input]
inputs += options.argv if not options.argv.empty?

begin
  inout = []
  current_loop = options.loops
  while current_loop != 0
    inputs.each do |input|
      #input = File.expand_path(input)
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
        unless Tools::FileTool::wait_for(i, options.inputWaitLoops, 2) {|loop, max| puts "waiting for #{opts.input}..." if loop == max }
          puts "#{opts.input} does not exist"
          next
        end
        opts.input = File.expand_path(i)
        hb_input = HBConvertInput.new(opts.input)
        results = Handbrake::convert(opts, titleMatcher, audioMatcher, subtitleMatcher)
        inout << [hb_input, results]
      end
    end
    current_loop -= 1
  end
rescue Interrupt
  puts "CTRL-C detected - stopping conversion"
end

# default overview
if options.logOverview.nil?
  overview = nil
else
  overview = File.open(options.logOverview, options.logOverride ? "w" : "a")
end

write_overview = lambda{|msg|
  HandbrakeCLI::logger.warn("#{msg}")
  overview.puts("#{msg}") unless overview.nil?  
}

begin
  write_overview.call("overview")
  inout.each do |input,results|
    write_overview.call("input: #{input}")
    if results.empty?
      write_overview.call("  no outputs")
    else
      results.each do |result|
        write_overview.call("  #{result.file} (#{result.fileSize})")
        unless result.output.nil?
          result.output.titles.each do |title|
            write_overview.call("    title #{title.pos} #{title.duration}, #{title.size}, #{title.fps}fps")
            unless title.audioTracks.empty?
              write_overview.call("      audio-tracks:")
              title.audioTracks.each do |t|
                write_overview.call("        track #{t.pos}. #{t.descr} (#{t.lang})")  
              end
            end
            unless title.subtitles.empty?
              write_overview.call("      subtitles:")
              title.subtitles.each do |t|
                write_overview.call("        track #{t.pos}. #{t.descr} (#{t.lang})")  
              end
            end
          end
        end
      end
    end
  end
ensure
  overview.close unless overview.nil?
end

HandbrakeCLI::logger.close()