#!/usr/bin/ruby

require 'optparse'
require 'lib/tools.rb'

class Ripper
  
  class RipperConfig

    def initialize(settings)
      @settings = settings
    end
    
    def id()
      @settings["id"]
    end
    
    def description()
      @settings["description"]
    end
    
    def file_output()
      @settings["fileoutput"]
    end
    
    def directories()
      d = @settings["directories"]
      return nil if d.nil?
      return d.split(/,\s*/)
    end
    
    def executable()
      @settings["executable"]
    end
    
    def arguments(type = nil)
      unless type.nil?
        args = @settings["arguments.#{type}"] 
        return args unless args.nil?
      end 
      @settings["arguments"]
    end
    
    def available?
      return !find_executable().nil?
    end
    
    def find_executable()
      exec = executable()
      return nil if exec.nil?
      dirs = (directories || [])
      dirs.each do |d|
        d.gsub!(/#conf_dir#/, PROFILE_DIR)
        d.gsub!(/%([^\s])*%/) {|m| ENV[m[1..-2]] || m }
        path = File.join(d, exec)
        return path if File.exist?(path) and File.executable?(path)
      end
      return Tools::OS::command2?(exec)
    end
    
    def file_type(input)
      return nil if not File.exist?(input)
      return "dev" if File.stat(input).blockdev? or File.stat(input).chardev?
      return "dir" if File.directory?(input)
      return File.extname(outputFile).downcase[1..-1]
    end

    def rip(input, output)
      ft = file_type(input)
      exec = find_executable()
      return false if ft.nil? or exec.nil?
      args = arguments(ft)
      return false if arguments.nil?
      args.gsub!(/#input#/, input)
      args.gsub!(/#output#/, output)
      unless file_output.nil?
        # create target dir
        dir = file_output ? File.dirname(output) : output
        File.makedirs(dir) if not File.exist?(dir)
      end
      cmd = "#{exec} #{args}"
      puts cmd
      system cmd
      return true
    end
    
    def to_s
      "#{id}: #{description} (executable=#{executable}, arguments=#{arguments})"
    end
  end
  PROFILE_DIR = File.join(File.dirname(File.expand_path($0)), "ripper", Tools::OS::platform().to_s().downcase)
  
  @@rippers = nil
  
  def self.formats
    return rippers.keys()
  end
  
  def self.rip(input, output, options)
    if not options.ripper_id.nil?
      ripper = rippers[options.ripper_id]
      raise "found no available ripper with id #{options.ripper_id}" if options.ripper_id.nil?
    end
    rippers.values.each do |r|
      if r.available?
        ripper = r
        break
      end
    end
    return false if ripper.nil?
    return ripper.rip(input, output)
  end
    
  def self.rippers
    return @@rippers unless @@rippers.nil?
    @@rippers = {}
    Dir[File.join("#{PROFILE_DIR}/*.conf")].each do |cfg|
      settings = {}
      id = File::basename(cfg, ".conf")
      File.readlines(cfg).each do |line|
        line.strip!
        next if line.empty?
        next if line.start_with?("#")
        kv = line.split("=", 2)
        kv.first.strip!
        kv.last.strip!
        next if kv.first.empty?
        kv.last = nil if kv.last.empty?
        settings[kv.first] = kv.last
      end
      unless settings.empty?
        raise "there is already a registered ripper with id #{id}" if @@rippers[id]
        settings["id"] = id
        @@rippers[id] = RipperConfig.new(settings)
      end
    end
    return @@rippers
  end
end

def showUsageAndExit(options, msg = nil)
  puts options.to_s
  puts ""
  puts "rippers"
  Ripper::rippers().values.each() {|r| puts " - #{r}" if r.available? }
  puts ""
  if not msg.nil?
    puts msg
    puts
  end
  exit
end

options = Struct.new(:input, :output, :ripper_id).new

ARGV.options do |opts|
  opts.on("--input INPUT", "input") { |arg| options.input = arg }
  opts.on("--output OUTPUT", "output") { |arg| options.output = arg }
  opts.on("--ripper ID", "the ripper to use") { |arg| options.ripper_id = arg }
  opts.on("--help", "Display this screen") { |arg| showUsageAndExit(opts.to_s) }
end

begin
  ARGV.parse!
rescue => e
  if not e.kind_of?(SystemExit)
    showUsageAndExit(ARGV.options, e.to_s)
  else
    exit
  end
end

showUsageAndExit(ARGV.options,"input not set") if options.input.nil?
showUsageAndExit(ARGV.options,"output not set") if options.output.nil?

Ripper::rip(options.input, options.output, options)
