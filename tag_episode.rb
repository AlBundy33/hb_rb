#!/usr/bin/env ruby
require 'optparse'
require './lib/tools.rb'
require './lib/taggers.rb'
require './lib/provider_lib.rb'

def showUsageAndExit(options, msg = nil)
  puts options
  if not msg.nil?
    puts
    puts msg
  end
  puts
  exit
end

providers = {}
providers["sj"] = SerienjunkiesProvider.new
providers["imdb"] = ImdbProvider.new

options = Struct.new(:identifier, :name, :season, :episode, :rename, :tag, :test, :append_old_name, :pattern, :provider).new
options.pattern = "#name# - #season#x#episode# - #title# (#title_org#).#filename#"
options.provider = "sj"
provider_list = ""
providers.each{|k,v| provider_list << "\n\t\t#{k}: #{v.name}"}
ARGV.options do |opts|
  opts.on("--provider PROVIDER", "tag-provider#{provider_list}") do |arg|
    options.provider = arg
  end
  opts.on("--id ID", "series ID (depending on provider)") do |arg|
    options.identifier = arg
  end
  opts.on("--season NUM", "season number") do |arg|
    options.season = arg.to_i
  end
  opts.on("--episode NUM", "episode number") do |arg|
    options.episode = arg.to_i
  end
  opts.on("--name NAME", "series name (overrides name from provider)") do |arg|
    options.name = arg
  end
  opts.on("--test", "test-only") do |arg|
    options.test = arg
  end
  opts.on("--tag", "tag file") do |arg|
    options.tag = arg
  end
  opts.on("--rename", "rename file") do |arg|
    options.rename = arg
  end
  opts.on("--pattern PATTERN", "pattern for the new name (default: #{options.pattern})") do |arg|
    options.pattern = arg
  end
  opts.on("--help", "Display this screen") do
    showUsageAndExit(opts.to_s)
  end
end

ARGV.parse!
showUsageAndExit(ARGV.options, "no file set") if ARGV.empty?
showUsageAndExit(ARGV.options, "no id set") if options.identifier.nil?
showUsageAndExit(ARGV.options, "no season set") if options.season.nil?
showUsageAndExit(ARGV.options, "no episode set") if options.episode.nil?
showUsageAndExit(ARGV.options, "choose rename and/or tag") if options.rename.nil? and options.tag.nil? and !options.test
showUsageAndExit(ARGV.options, "unknown provider #{options.provider}") if providers[options.provider].nil? 

season = options.season
episode = options.episode
ARGV.each do |f|
  info = providers[options.provider].load(options.identifier, season, episode)
  info.name = options.name unless options.name.nil?
  if options.test
    puts f
    info.to_map.each {|k,v| puts "\t#{k} = #{v}" }
  end

  if options.tag
    tagger = TaggerFactory::newTagger()
    cmd = tagger.createCommand(f, info.to_map)
    if cmd.nil?
      Tools::CON.warn("found no command to tag file")
    else
      Tools::CON.info("tagging file: #{cmd}")
      system(cmd) unless options.test
    end
  end
  
  if options.rename
    new_name = options.pattern.dup
    info.to_map.each do |k,v|
      new_name.gsub!(/##{k}#/, v)
    end
    new_name.gsub!(/#filename#/, File.basename(f, ".*"))
    new_name = new_name + File.extname(f)
    new_name = File.expand_path(File.join(File.dirname(f), new_name))
    if not File.expand_path(f).eql?(new_name)
      if File.exist?(new_name)
        Tools::CON.warn("cannot rename #{f} to #{new_name} because target already exist")
      else 
        Tools::CON.info("renaming\n\tfile: #{f}\n\t  to: #{new_name}")
        File.rename(f, new_name) unless options.test
      end
    end  
  end

  episode += 1
end
