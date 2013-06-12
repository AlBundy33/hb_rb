#!/usr/bin/ruby
require 'optparse'
require './lib/tools.rb'
require './lib/taggers.rb'
require './lib/sj_lib.rb'

class TagData
  attr_accessor :name, :season, :episode, :title_de, :title_en, :descr, :sj_url
  def initialize(name, season, episode)
    @name = name
    @season = season
    @episode = episode
  end

  def to_s
    "%s - %02dx%02d - %s (%s)\n%s" % [@name, @season, @episode, @title_de, @title_en, @descr]
  end
  
  def to_map
    {
      "season" => "#{season}",
      "episode" => "#{episode}",
      "name" => "#{name}",
      "title" => "#{title_de}"
    }
  end
end

def showUsageAndExit(options, msg = nil)
  puts options
  if not msg.nil?
    puts
    puts msg
  end
  puts
  exit
end

options = Struct.new(:sjid, :name, :season, :episode, :rename, :tag, :file).new
ARGV.options do |opts|
  opts.on("--file FILE", "the file") do |arg|
      options.file = arg
    end
  opts.on("--id SJID", "serienjunkies-id") do |arg|
    options.sjid = arg
  end
  opts.on("--season NUM", "season number") do |arg|
    options.season = arg.to_i
  end
  opts.on("--episode NUM", "episode number") do |arg|
    options.episode = arg.to_i
  end
  opts.on("--name NAME", "series name") do |arg|
    options.name = arg
  end
  opts.on("--rename", "rename file") do |arg|
    options.rename = arg
  end
  opts.on("--tag", "tag file") do |arg|
    options.tag = arg
  end
  opts.on("--help", "Display this screen") do
    showUsageAndExit(opts.to_s)
  end
end

ARGV.parse!
showUsageAndExit(ARGV.options, "no file set") if options.file.nil?
showUsageAndExit(ARGV.options, "no id set") if options.sjid.nil?
showUsageAndExit(ARGV.options, "no season set") if options.season.nil?
showUsageAndExit(ARGV.options, "no episode set") if options.episode.nil?
showUsageAndExit(ARGV.options, "choose rename and/or tag") if options.rename.nil? and options.tag.nil? 

info = Serienjunkies::load(options.sjid, options.season, options.episode)
info.name = options.name unless options.name.nil?

if options.tag
  tagger = TaggerFactory::newTagger()
  cmd = tagger.createCommand(options.file, info.to_map)
  if cmd.nil?
    Tools::CON.warn("found no command to tag file")
  else
    Tools::CON.info("tagging file: #{cmd}")
    system(cmd)
  end
end

if options.rename
  new_name = "%s - %02dx%02d - %s (%s)" % [info.name, info.season, info.episode, info.title_de, info.title_en]
  new_name = new_name + File.extname(options.file)
  new_name = File.expand_path(File.join(File.dirname(options.file), new_name))
  if not File.expand_path(options.file).eql?(new_name)
    if File.exist(new_file)
      Tools::CON.warn("cannot rename #{options.file} to #{new_name} because target already exist")
    else 
      Tools::CON.info("renaming #{options.file} to #{new_name}")
      File.rename(options.file, new_name)
    end
  end  
end
