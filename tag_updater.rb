#!/usr/bin/ruby

require 'optparse'
require 'csv'
require 'ostruct'
require 'lib/tools.rb'
require 'lib/taggers.rb'

class TagDb
  attr_accessor :data, :dir, :db, :debug
  L = Tools::Loggers.console()
  DB_NAME = "tags.csv"
  INFO_DATA = [ "path", "name", "title", "season", "episode", "disc", "track", "descr" ]

  def initialize(dir, debug)
    @data = {}
    @dir = File.expand_path(dir)
    @db = File.expand_path("#{dir}/#{DB_NAME}")
    @debug = debug
    load()
  end
  
  def load()
    if File.exists? db
      first = true
      CSV.open(db, "r", ";") do |row|
        if first
          first = false
          next
        end
        info = {}
        for i in 0..INFO_DATA.length
          info[INFO_DATA[i]] = row[i]
        end
        data[info["path"]] = info
      end
    end
  end
  
  def save()
    k = data.keys.sort
    writer = CSV.open(db,"w", ";")
    begin
      writer << INFO_DATA
      k.each do |key|
        info = data[key]
        row = []
        for i in 0..INFO_DATA.length
          row[i] = info[INFO_DATA[i]]
        end
        writer << row
      end
    ensure
      writer.close
    end
  end
  
  def updateTags(pattern)
    pattern = "**/*.mp4" if pattern.nil?  
    Dir["#{dir}/#{pattern}"].each do |f|
      next if not File.exists? f
      file = filename(f)
      info = data[file]
      if info.nil?
        L.warn("found no tags for #{file}")
        next
      end
      cmd = TaggerFactory.newTagger().createCommand(f, info)
      if cmd.nil?
        L.warn("could not create command to tag file #{file}")
        next
      end
      cmd = Tools::Tee::command(cmd,File.expand_path("tag.log"),true)
      L.info("#{cmd}")
      %x[#{cmd}] if not debug
    end
  end

  def filename(file)
    f = File.expand_path(file)
    f = f[dir.length + 1, f.length - dir.length] if f.start_with? dir
    return f 
  end
  
  def updateDb()
    Dir["#{dir}/**/*.mp4"].each { |f|
      L.info("updating #{f}")
      mp4 = filename(f)
      tmp = mp4.split("/")
      info = data[mp4]
      info = {} if info.nil?

      info["path"] = mp4
      info["name"] = tmp[0]
      #info["season"] = tmp[1].gsub(/[^0-9]/, "")
      pattern = /.*_S([0-9]+)D([0-9]+)T([0-9]+)\.mp4/
      info["season"] = tmp[2].gsub(pattern, "\\1")
      info["disc"] = tmp[2].gsub(pattern, "\\2")
      info["track"] = tmp[2].gsub(pattern, "\\3")

      data[info["path"]] = info
    }
    
    # update episodes
    last_season = -1
    episode = -1
    k = data.keys.sort
    k.each do |key|
      info = data[key]

      season = info["season"].to_i

      if not info["episode"].nil?
        episode = info["episode"].to_i
        next
      end

      episode = 1 if not season == last_season
      info["episode"] = episode.to_s

      episode += 1
      last_season = season
    end

    save
  end
end

options = OpenStruct.new
options.updatedb = false
options.updatetags = false
options.pattern = nil
options.debug = false
options.directory = File.expand_path(".")

optparse = OptionParser.new do |opts|
  opts.on("--updatedb", "update tag-database") do |arg|
    options.updatedb = arg
  end
  opts.on("--updatetags", "update tags") do |arg|
    options.updatetags = arg
  end
  opts.on("--dir DIRECTORY", "the directory containing the mp4-files") do |arg|
    options.directory = arg
  end
  opts.on("--files PATTERN", "the pattern for the files to update") do |arg|
    options.pattern = arg
  end
  opts.on("--debug", "debug-mode") do |arg|
    options.debug = arg
  end
  opts.on("--help", "Display this screen") do
    puts opts
    exit
  end
end

optparse.parse!(ARGV)

db = TagDb.new(options.directory, options.debug)
db.updateDb() if options.updatedb
db.updateTags(options.pattern) if options.updatetags
