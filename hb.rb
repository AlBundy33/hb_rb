#!/usr/bin/ruby

require 'optparse'
require 'tmpdir'
require 'ostruct'

class Handbrake
  require 'fileutils'  
  require 'lib/tools.rb'
  include Tools
  
  L = Tools::Loggers.console()

  if Tools::OS::windows?
    HANDBRAKE_CLI = File.expand_path("tools/handbrake/windows/HandBrakeCLI")
  else
    HANDBRAKE_CLI = File.expand_path("tools/handbrake/osx/HandBrakeCLI")
  end

  attr_accessor :options
  
  def initialize()
    raise "handbrake not found" if HANDBRAKE_CLI.nil?
  end

  def readDvd(options)
    path = File.expand_path(options.input)
    output = %x["#{HANDBRAKE_CLI}" -i "#{path}" --scan -t 0 2>&1]
    main_feature_pattern = /\+ Main Feature/
    title_blocks_pattern = /\+ vts .*, ttn .*, cells .* \(([0-9]+) blocks\)/
    title_pattern = /\+ title ([0-9]+):/
    title_info_pattern = /\+ size: ([0-9]+x[0-9]+).*, ([0-9.]+) fps/
    audio_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\), ([0-9]+Hz), ([0-9]+bps)/
    subtitle_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\)/
    duration_pattern = /\+ duration: (.*)/
    chapter_pattern = /\+ ([0-9]+): cells .* duration (.*)/
    dvd = Dvd.new(path)
    title = nil
    output.each_line do |line|
      ##L.debug("### #{line}") if options.debug and options.verbose
      puts "### #{line}" if options.debug and options.verbose
      if line.match(title_pattern)
        info = line.scan(title_pattern)[0]
        title = Title.new(info[0])
        dvd.titles().push(title)
      end

      next if title.nil?

      if line.match(main_feature_pattern)
        title.mainFeature = true
      elsif line.match(title_blocks_pattern)
        info = line.scan(title_blocks_pattern)[0]
        title.blocks = info[0].to_i
      elsif line.match(title_info_pattern)
        info = line.scan(title_info_pattern)[0]
        title.size = info[0]
        title.fps = info[1]
      elsif line.match(duration_pattern)
        info = line.scan(duration_pattern)[0]
        title.duration = info[0]
      elsif line.match(chapter_pattern)
        info = line.scan(chapter_pattern)[0]
        chapter = Chapter.new(info[0])
        chapter.duration = info[1]
        title.chapters().push(chapter)
      elsif line.match(audio_pattern)
        info = line.scan(audio_pattern)[0]
        track = AudioTrack.new(info[0],info[2], info[1])
        title.audioTracks().push(track)
      elsif line.match(subtitle_pattern)
        info = line.scan(subtitle_pattern)[0]
        subtitle = Subtitle.new(info[0],info[2], info[1])
        title.subtitles().push(subtitle)
      end
    end
    return dvd
  end

  def ripDvd(options, dvd, titleMatcher, audioMatcher, subtitleMatcher)
    ripped = []
    output = options.output
    preset = options.preset
    mainFeatureOnly = options.mainFeatureOnly || false
    force = options.force || false
    skipDuplicates = options.skipDuplicates || false
    verbose = options.verbose || false
    debug = options.debug || false
    mixdownOnly = options.mixdownOnly || false
    copyOnly = options.copyOnly || false
    xtraArgs = options.xtra_args
    minLength = TimeTool::timeToSeconds(options.minLength)
    maxLength = TimeTool::timeToSeconds(options.maxLength)
    ipodCompatibility = options.ipodCompatibility || false

    dvd.titles().each do |title|
      if titleMatcher.matches(title) and (not mainFeatureOnly or (mainFeatureOnly and title.mainFeature))
        L.info("#{title}")
        tracks = audioMatcher.filter(title.audioTracks).collect{|e| e.pos}
        subtitles = subtitleMatcher.filter(title.subtitles).collect{|e| e.pos}
          
        duration = TimeTool::timeToSeconds(title.duration)
        if minLength >= 0 and duration < minLength
          L.info("skipping title because it's duration is too short (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})")
          next
        end
        if maxLength >= 0 and duration > maxLength
          L.info("skipping title because it's duration is too long (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})")
          next
        end
        if tracks.empty?() or tracks.length < audioMatcher.allowed().length
          L.info("skipping title because it contains not all wanted audio-tracks (available: #{tracks})")
          next
        end
        if skipDuplicates and title.blocks() >= 0 and ripped.include?(title.blocks())
          L.info("skipping because disc contains it twice")
          next
        end

        extra_arguments = xtraArgs
        outputFile = File.expand_path(output)
        outputFile = outputFile.gsub("#pos#", "%02d" % title.pos)
        outputFile = outputFile.gsub("#size#", title.size)
        outputFile = outputFile.gsub("#fps#", title.fps)
        outputFile = outputFile.gsub("#input#", File.basename(dvd.path()))
        
        command="\"#{HANDBRAKE_CLI}\""
        command << " --input \"#{dvd.path()}\""
        command << " --output \"#{outputFile}\""
        command << " --verbose" if verbose
        if not preset.nil? and not preset.empty? 
          command << " --preset \"#{preset}\""
        else
          # video
          vbr = 2000
          x264_quality = nil
          x264_quality_opts = nil
          x264_quality = "20.0"

          # iPod
          if ipodCompatibility
            x264_quality_opts = "level=30:bframes=0:weightp=0:cabac=0:8x8dct=0:ref=1:vbv-maxrate=#{vbr}:vbv-bufsize=2500:analyse=all:me=umh:no-fast-pskip=1:psy-rd=0,0:subme=6:trellis=0"
          end
          
          # https://forum.handbrake.fr/viewtopic.php?f=6&t=19426
          # ultrafast
          #x264_quality_opts = "ref=1:bframes=0:cabac=0:8x8dct=0:weightp=0:me=dia:subq=0:rc-lookahead=0:mbtree=0:analyse=none:trellis=0:aq-mode=0:scenecut=0:no-deblock=1"
          # superfast
          #x264_quality_opts = "ref=1:weightp=1:me=dia:subq=1:rc-lookahead=0:mbtree=0:analyse=i4x4,i8x8:trellis=0"
          # veryfast
          #x264_quality_opts = "ref=1:weightp=1:subq=2:rc-lookahead=10:trellis=0"
          # faster
          #x264_quality_opts = "ref=2:mixed-refs=0:weightp=1:subq=4:rc-lookahead=20"
          # fast
          #x264_quality_opts = "ref=2:weightp=1:subq=6:rc-lookahead=30"
          # slow
          #x264_quality_opts = "ref=5:b-adapt=2:direct=auto:me=umh:subq=8:rc-lookahead=50"
          # slower
          #x264_quality_opts = "ref=8:b-adapt=2:direct=auto:me=umh:subq=9:rc-lookahead=60:analyse=all:trellis=2"
          # veryslow
          #x264_quality_opts = "ref=16:bframes=8:b-adapt=2:direct=auto:me=umh:merange=24:subq=10:rc-lookahead=60:analyse=all:trellis=2"
          # placebo
          #x264_quality_opts = "ref=16:bframes=16:b-adapt=2:direct=auto:me=tesa:merange=24:subq=10:rc-lookahead=60:analyse=all:trellis=2:no-fast-pskip=1"
          command << " --encoder x264"
          if x264_quality.nil?
            command << " --vb #{vbr}"
            command << " --two-pass"
            command << " --turbo"
          else
            command << " --quality #{x264_quality}"
          end

          # append for iPod-compatibility
          if ipodCompatibility
            command << " --ipod-atom"

            if x264_quality_opts.nil?
              x264_quality_opts  = ""
            else
              x264_quality_opts << ":"
            end
            x264_quality_opts << "level=30:bframes=0:cabac=0:weightp=0:8x8dct=0"
          end
          
          # tune encoder
          command << " -x #{x264_quality_opts}" if not x264_quality_opts.nil?

          command << " --decomb"
          command << " --detelecine"
          command << " --crop 0:0:0:0"
          # audio
          if mixdownOnly
            # create only mixdown track
            command << " --audio #{tracks.join(",")}"
            command << " --aencoder #{Array.new(tracks.length, "faac").join(",")}"
            command << " --arate #{Array.new(tracks.length, "auto").join(",")}"
            command << " --mixdown #{Array.new(tracks.length, "dpl2").join(",")}"
            command << " --ab #{Array.new(tracks.length, "160").join(",")}"
          elsif copyOnly
            # copy original track
            command << " --audio #{tracks.join(",")}"
            command << " --aencoder #{Array.new(tracks.length, "copy").join(",")}"
            command << " --arate #{Array.new(tracks.length, "auto").join(",")}"
            command << " --mixdown #{Array.new(tracks.length, "auto").join(",")}"
            command << " --ab #{Array.new(tracks.length, "auto").join(",")}"
            command << " --audio-fallback faac"
          else
            # copy original and create mixdown track
            command << " --audio "
            tracks.each do |t|
              command << "#{t},#{t},"
            end
            command.chomp!(",")
            command << " --aencoder #{Array.new(tracks.length, "copy,faac").join(",")}"
            command << " --arate #{Array.new(tracks.length, "auto,auto").join(",")}"
            command << " --mixdown #{Array.new(tracks.length, "auto,dpl2").join(",")}"
            command << " --ab #{Array.new(tracks.length, "auto,160").join(",")}"            
          end
          # common
          command << " --format mp4"
          command << " --markers"
          command << " --optimize"
        end
        command << " --title #{title.pos}"
        command << " --subtitle #{subtitles.join(",")}" if not subtitles.empty?()
        command << " " << extra_arguments if not extra_arguments.nil?() and not extra_arguments.empty?
        command << " 2>&1"
        
        ripped.push(title.blocks())
        if force or (not File.exists?(outputFile) and Dir.glob("#{File.dirname(outputFile)}/*.#{File.basename(outputFile)}").empty?)
          L.info(command)
          if not debug
            parentDir = File.dirname(outputFile)
            FileUtils.mkdir_p(parentDir) unless File.directory?(parentDir)
            system command
            if File.exists?(outputFile)
              if File.size(outputFile) < (1 * 1024 * 1024)
                L.warn("file-size only #{File.size(outputFile) / 1024} KB - removing file")
                File.delete(outputFile)
                ripped.delete(title.blocks())
              else
                L.info("file #{outputFile} created")
              end
            else
              L.warn("file #{outputFile} not created")
            end
          end
        else
          if File.exists?(outputFile)
            f = outputFile
          else
            f = Dir.glob("#{File.dirname(outputFile)}/*.#{File.basename(outputFile)}").join(", ")
          end
          L.info("skipping title because \"#{f}\" already exists")
        end
      end
    end
  end
end

class Chapter
  attr_accessor :pos, :duration
  def initialize(pos)
    @pos = pos.to_i
    @duration = "unknown"
  end

  def to_s
    "#{pos}. #{duration}"
  end
end

class Subtitle
  attr_accessor :pos, :lang, :desc
  def initialize(pos, lang, desc)
    @pos = pos.to_i
    @lang = lang
    @desc = desc
  end

  def to_s
    "#{pos}. #{desc} (#{lang})"
  end
end

class AudioTrack
  attr_accessor :pos, :lang, :desc
  def initialize(pos, lang, desc)
    @pos = pos.to_i
    @lang = lang
    @desc = desc
  end

  def to_s
    "#{pos}. #{desc} (#{lang})"
  end
end

class Title
  attr_accessor :pos, :audioTracks, :subtitles, :chapters, :size, :fps, :duration, :mainFeature, :blocks
  def initialize(pos)
    @pos = pos.to_i
    @blocks = -1
    @audioTracks = []
    @subtitles = []
    @chapters = []
    @size = "unknown"
    @fps = "unknown"
    @duration = "unknown"
    @mainFeature = false
  end

  def to_s
    "title #{"%02d" % pos}: #{duration}, #{size}, #{fps} fps, main-feature: #{mainFeature()}, blocks: #{blocks}, chapters: #{chapters.length}, audio-tracks: #{audioTracks.collect{|t| t.lang}.join(",")}, subtitles: #{subtitles.collect{|s| s.lang}.join(",")}"
  end
end

class Dvd
  attr_accessor :titles, :path
  def initialize(path)
    @titles = []
    @path = path
  end
  
  def info
    s = "#{self}"
    titles().each do |t|
      s << "\n#{t}"
      s << "\n  audio-tracks:"
      t.audioTracks().each do |e|
        s << "\n    #{e}"
      end
      s << "\n  subtitles:"
      t.subtitles().each do |e|
        s << "\n    #{e}"
      end
    end
    s
  end

  def to_s
    "#{path}"
  end
end

class ValueMatcher
  attr_accessor :allowed
  def initialize(allowed)
    @allowed = allowed
  end
  
  def value(obj)
    raise "method not implemented"
  end
  
  def matches(obj)
    allowed().nil? or allowed().include?(value(obj))
  end

  def filter(list, onlyFirst = false)
    return list if allowed().nil?

    filtered = []
    stack = []
    allowed().each do |a|
      list.each do |e|
        v = value(e)
        if (v == a or v.eql? a) and not stack.include? v
          stack.push v
          filtered.push e
          break if onlyFirst
        end
      end
    end
    return filtered
  end
  
  def to_s
    "#{@allowed}"
  end
end

class PosMatcher < ValueMatcher
  def value(obj)
    obj.pos
  end
end

class LangMatcher < ValueMatcher
  def value(obj)
    obj.lang
  end
end

options = OpenStruct.new
optparse = OptionParser.new do |opts|
  
  opts.separator("")
  opts.separator("options")
  opts.on("--input INPUT", "input-source") do |arg|
    options.input = arg
  end
  opts.on("--output OUTPUT", "output-directory") do |arg|
    options.output = arg
  end
  opts.on("--force", "force override of existing files") do |arg|
    options.force = arg
  end

  opts.separator("")
  opts.separator("output-options")
  opts.on("--preset PRESET", "the preset to use") do |arg|
    options.preset = arg
  end
  opts.on("--compatibility", "enables iPod compatible output") do |arg|
    options.ipodCompatibility = arg
  end
  opts.on("--audio LANGUAGES", Array, "the audio languages") do |arg|
    options.languages = arg
  end 
  opts.on("--mixdown-only", "create only mixed down track") do |arg|
    options.mixdownOnly = arg
  end
  opts.on("--copy-only", "copy original-audio track") do |arg|
    options.copyOnly = arg
  end
  opts.on("--subtitles LANGUAGES", Array, "the subtitle languages") do |arg|
    options.subtitles = arg
  end

  opts.separator("")
  opts.separator("filter-options")
  opts.on("--main", "main-feature only") do |arg|
    options.mainFeatureOnly = arg
  end
  opts.on("--titles TITLES", Array, "the title-numbers to rip (use --check to see available titles)") do |arg|
    options.titles = arg
  end
  opts.on("--min-length DURATION", "the minimum-track-length - format hh:nn:ss") do |arg|
    options.minLength = arg
  end
  opts.on("--max-length DURATION", "the maximum-track-length - format hh:nn:ss") do |arg|
    options.maxLength = arg
  end
  opts.on("--skip-duplicates", "skip duplicate tracks (checks block-size)") do |arg|
    options.skipDuplicates = arg
  end
  
  opts.separator("")
  opts.separator("expert-options")
  opts.on("--check", "run check only and display information") do |arg|
    options.checkOnly = arg
  end
  opts.on("--xtra ARGS", "additional arguments for handbrake") do |arg|
    options.xtra_args = arg
  end
  opts.on("--debug", "enable debug-mode (doesn't start ripping)") do |arg|
    options.debug = arg
  end
  opts.on("--verbose", "enable verbose output") do |arg|
    options.verbose = arg
  end
 
  opts.on_tail("--help", "Display this screen") do
    puts opts
    exit
  end
end

begin
  optparse.parse!(ARGV)
rescue OptionParser::InvalidOption => e
  puts optparse
  puts
  puts e
  exit 1
end

titles = nil
if not options.titles.nil?
  titles = []
  range_pattern = /([0-9]+)-([0-9]+)/
  options.titles.each do |t| 
    if t.match(range_pattern)
      range = t.scan(range_pattern)[0]
      rangeStart = range[0].to_i
      rangeEnd = range[1].to_i
      rangeStart.upto(rangeEnd) { |n| titles.push(n) unless titles.include?(n) } 
    else
      titles.push(t.to_i) unless titles.include?(t.to_i)
    end
  end
end

options.languages = ["deu"] if options.languages.nil?()
options.subtitles = [] if options.subtitles.nil?()

if options.input.nil?() or (not options.checkOnly and options.output.nil?())
  puts optparse
  exit
end

if not File.exist? options.input
  puts "\"#{options.input}\" does not exist"
  exit
end

hb = Handbrake.new
dvd = hb.readDvd(options)

titleMatcher = PosMatcher.new(titles)
audioMatcher = LangMatcher.new(options.languages)
subtitleMatcher = LangMatcher.new(options.subtitles)

if options.checkOnly
  puts dvd.info
else
  hb.ripDvd(options, dvd, titleMatcher, audioMatcher, subtitleMatcher)
end
