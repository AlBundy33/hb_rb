#!/usr/bin/ruby

require 'optparse'
require 'logger'

class Handbrake
  require 'fileutils'
  require 'lib/tools.rb'
  include Tools

  HANDBRAKE_CLI = File.expand_path("tools/handbrake/#{Tools::OS::platform()}/HandBrakeCLI")
  raise "#{HANDBRAKE_CLI} does not exist" if not Tools::OS::command2?(HANDBRAKE_CLI)
  
  AUDIO_ENCODERS = %w(ca_aac ca_haac faac ffaac ffac3 lame vorbis ffflac)
  AUDIO_MIXDOWNS = %w(mono stereo dpl1 dpl2 6ch)

  X264_PROFILES = %w(baseline main high high10 high422 high444)
  X264_PRESETS = %w(ultrafast superfast veryfast faster fast medium slow slower veryslow placebo)
  X264_TUNES = %w(film animation grain stillimage psnr ssim fastdecode zerolatency)
  
  def self.getPresets()
    cmd = "\"#{HANDBRAKE_CLI}\" --preset-list 2>&1"
    output = %x[#{cmd}]
    preset_pattern = /\+ (.*?): (.*)/
    result = [] 
    output.each_line do |line|
      next if not line =~ preset_pattern
      info = line.scan(preset_pattern)[0]
      result << [info[0], info[1]]
    end
    return result
  end

  def self.readInfo(options)
    path = File.expand_path(options.input)
    cmd = "\"#{HANDBRAKE_CLI}\" -i \"#{path}\" --scan -t 0 2>&1"
    output = %x[#{cmd}]

    dvd_title_pattern = /libdvdnav: DVD Title: (.*)/
    dvd_alt_title_pattern = /libdvdnav: DVD Title \(Alternative\): (.*)/
    dvd_serial_pattern = /libdvdnav: DVD Serial Number: (.*)/
    main_feature_pattern = /\+ Main Feature/

    title_blocks_pattern = /\+ vts .*, ttn .*, cells .* \(([0-9]+) blocks\)/
    title_pattern = /\+ title ([0-9]+):/
    title_info_pattern = /\+ size: ([0-9]+x[0-9]+).*, ([0-9.]+) fps/
    in_audio_section_pattern = /\+ audio tracks:/
    audio_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\), ([0-9]+Hz), ([0-9]+bps)/
    file_audio_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\)/
    in_subtitle_section_pattern = /\+ (subtitles|subtitle tracks):/
    subtitle_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\)/
    duration_pattern = /\+ duration: (.*)/
    chapter_pattern = /\+ ([0-9]+): cells (.*), ([0-9]+) blocks, duration (.*)/

    source = MovieSource.new(path)
    title = nil

    in_audio_section = false
    in_subtitle_section = false
    output.each_line do |line|
      puts "out> #{line}" if options.debug and options.verbose

      if line.match(dvd_title_pattern)
        puts "> match: dvd-title" if options.debug and options.verbose
        info = line.scan(dvd_title_pattern)[0]
        source.title = info[0].strip
      elsif line.match(dvd_alt_title_pattern)
        puts "> match: dvd-alt-title" if options.debug and options.verbose
        info = line.scan(dvd_alt_title_pattern)[0]
        source.title_alt = info[0].strip
      elsif line.match(dvd_serial_pattern)
        puts "> match: dvd-serial" if options.debug and options.verbose
        info = line.scan(dvd_serial_pattern)[0]
        source.serial = info[0].strip
      elsif line.match(in_audio_section_pattern)
        in_audio_section = true
        in_subtitle_section = false
      elsif line.match(in_subtitle_section_pattern)
        in_audio_section = false
        in_subtitle_section = true
      elsif line.match(title_pattern)
        puts "> match: title" if options.debug and options.verbose
        info = line.scan(title_pattern)[0]
        title = Title.new(info[0])
        source.titles().push(title)
      end

      next if title.nil?

      if line.match(main_feature_pattern)
        puts "> match: main-feature" if options.debug and options.verbose
        title.mainFeature = true
      elsif line.match(title_blocks_pattern)
        puts "> match: blocks" if options.debug and options.verbose
        info = line.scan(title_blocks_pattern)[0]
        title.blocks = info[0].to_i
      elsif line.match(title_info_pattern)
        puts "> match: info" if options.debug and options.verbose
        info = line.scan(title_info_pattern)[0]
        title.size = info[0]
        title.fps = info[1]
      elsif line.match(duration_pattern)
        puts "> match: duration" if options.debug and options.verbose
        info = line.scan(duration_pattern)[0]
        title.duration = info[0]
      elsif line.match(chapter_pattern)
        puts "> match: chapter" if options.debug and options.verbose
        info = line.scan(chapter_pattern)[0]
        chapter = Chapter.new(info[0])
        chapter.cells = info[1]
        chapter.blocks = info[2]
        chapter.duration = info[3]
        title.chapters().push(chapter)
      elsif in_audio_section and line.match(audio_pattern)
        puts "> match: audio" if options.debug and options.verbose
        info = line.scan(audio_pattern)[0]
        track = AudioTrack.new(info[0], info[1])
        if info[1].match(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)
          info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)[0]
          track.codec = info2[0]
          track.comment = info2[1]
          track.channels = info2[2]
        elsif info[1].match(/\((.*?)\)\s*\((.*?)\)\s*/)
          info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*/)[0]
          track.codec = info2[0]
          track.channels = info2[1]
        end
        track.lang = info[2]
        track.rate = info[3]
        track.bitrate = info[4]
        title.audioTracks().push(track)
      elsif in_audio_section and line.match(file_audio_pattern)
        puts "> match: audio" if options.debug and options.verbose
        info = line.scan(file_audio_pattern)[0]
        track = AudioTrack.new(info[0], info[1])
        if info[1].match(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)
          info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)[0]
          track.codec = info2[0]
          track.comment = info2[1]
          track.channels = info2[2]
        elsif info[1].match(/\((.*?)\)\s*\((.*?)\)\s*/)
          info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*/)[0]
          track.codec = info2[0]
          track.channels = info2[1]
        end
        track.lang = info[2]
        title.audioTracks().push(track)
      elsif in_subtitle_section and line.match(subtitle_pattern)
        puts "> match: subtitle" if options.debug and options.verbose
        info = line.scan(subtitle_pattern)[0]
        subtitle = Subtitle.new(info[0], info[1], info[2])
        if info[1].match(/\((.*?)\)/)
          info2 = info[1].scan(/\((.*?)\)/)[0]
          subtitle.comment = info2[0]
        end
        title.subtitles().push(subtitle)
      end
    end
    source.titles().first().mainFeature = true if source.titles().size == 1
    return source
  end

  def self.convert(options, titleMatcher, audioMatcher, subtitleMatcher)
    source = Handbrake::readInfo(options)
    if options.checkOnly
      puts source.info
      return
    end
    
    if source.titles.empty?
      Tools::CON::info("#{source.path} contains no titles")
      return
    end

    converted = []
    if options.minLength.nil?
      minLength = -1
    else
      minLength = TimeTool::timeToSeconds(options.minLength)
    end
    if options.maxLength.nil?
      maxLength = -1
    else
      maxLength = TimeTool::timeToSeconds(options.maxLength)
    end

    source.titles().each do |title|
      Tools::CON.info("checking #{title}")
      
      if options.mainFeatureOnly and not title.mainFeature
        Tools::CON.info("skipping title because it's not the main-feature")
        next
      elsif not titleMatcher.matches(title)
        Tools::CON.info("skipping unwanted title")
        next
      end

      tracks = audioMatcher.filter(title.audioTracks, options.onlyFirstTrackPerLanguage, options.skipDuplicates)
      subtitles = subtitleMatcher.filter(title.subtitles, options.onlyFirstTrackPerLanguage, options.skipDuplicates)

      duration = TimeTool::timeToSeconds(title.duration)
      if minLength >= 0 and duration < minLength
        Tools::CON.info("skipping title because it's duration is too short (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})")
        next
      end
      if maxLength >= 0 and duration > maxLength
        Tools::CON.info("skipping title because it's duration is too long (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})")
        next
      end
      if tracks.empty?() or (!audioMatcher.allowed().nil? and tracks.length < audioMatcher.allowed().length)
        Tools::CON.info("skipping title because it contains not all wanted audio-tracks (available: #{title.audioTracks})")
        next
      end
      if options.skipDuplicates and title.blocks() >= 0 and converted.include?(title.blocks())
        Tools::CON.info("skipping because source contains it twice")
        next
      end

      outputFile = File.expand_path(options.output)
      outputFile = outputFile.gsub("#pos#", "%02d" % title.pos)
      outputFile = outputFile.gsub("#size#", title.size)
      outputFile = outputFile.gsub("#fps#", title.fps)
      outputFile = outputFile.gsub("#ts#", Time.new.strftime("%Y-%m-%d_%H_%M_%S"))
      outputFile = outputFile.gsub("#title#", source.name)
      if not options.force
        if File.exists?(outputFile) or Dir.glob("#{File.dirname(outputFile)}/*.#{File.basename(outputFile)}").size() > 0
          Tools::CON.info("skipping title because \"#{outputFile}\" already exists")
          next
        end
      end
      
      Tools::CON.info("converting #{title}")

      extra_arguments = options.xtra_args
      ext = File.extname(outputFile).downcase
      ismp4 = false
      ismkv = false
      if ext.eql?(".mp4") or ext.eql?(".m4v")
        ismp4 = true
      elsif ext.eql?(".mkv")
        ismkv = true
      else
        raise "error unsupported extension #{ext}"
      end

      command="\"#{HANDBRAKE_CLI}\""
      command << " --input \"#{source.path()}\""
      command << " --output \"#{outputFile}\""
      command << " --chapters #{options.chapters}" if not options.chapters.nil?
      command << " --verbose" if options.verbose
      if not options.preset.nil? and not options.preset.empty?
        command << " --preset \"#{preset}\""
      else
        # video
        command << " --encoder x264"
        command << " --x264-profile #{options.x264profile}" if not options.x264profile.nil?
        command << " --x264-preset #{options.x264preset}" if not options.x264preset.nil?
        command << " --x264-tune #{options.x264tune}" if not options.x264tune.nil?
        command << " --quality 20.0"

        # iPod-compatibility
        if ismp4
          if options.ipodCompatibility
            command << " --ipod-atom"
            command << " --encopts level=30:bframes=0:cabac=0:weightp=0:8x8dct=0"
          else
            command << " --large-file"
          end
          command << " --format mp4"
          command << " --optimize"
        elsif ismkv
          command << " --format mkv"
        end

        command << " --markers"

        # picture settings
        command << " --decomb"
        command << " --detelecine"
        command << " --crop 0:0:0:0" if not options.enableAutocrop
        if not options.ipodCompatibility
          command << " --loose-anamorphic"
          command << " --modulus 16"
        end
        command << " --maxHeight #{options.maxHeight}" if options.maxHeight

        # audio
        paudio = []
        paencoder = []
        parate = []
        pmixdown = []
        pab = []
        paname = []
        tracks.each do |t|
          Tools::CON.info("checking audio-track #{t}")
          next if options.skipCommentaries and t.commentary?
          if options.audioCopy
            # copy original track
            paudio << t.pos
            paencoder << "copy"
            parate << "auto"
            pmixdown << "auto"
            pab << "auto"
            paname << "#{t.descr}"
            Tools::CON.info("adding audio-track: #{t}")
          end
          if options.audioMixdown
            paudio << t.pos
            paencoder << "faac"
            parate << "auto"
            pmixdown << "dpl2"
            pab << "160"
            paname << "#{t.descr} (mixdown)"
            Tools::CON.info("adding mixed down audio-track: #{t}")
          end
          if not options.audioEncoder.nil?
            paudio << t.pos
            paencoder << options.audioEncoder
            parate << "auto"
            pmixdown << options.audioEncoderMixdown
            pab << options.audioEncoderBitrate
            paname << "#{t.descr} (#{options.audioEncoder})"
            Tools::CON.info("adding #{options.audioEncoder} encoded audio-track: #{t}") 
          end
        end
        command << " --audio #{paudio.join(',')}"
        command << " --aencoder #{paencoder.join(',')}"
        command << " --arate #{parate.join(',')}"
        command << " --mixdown #{pmixdown.join(',')}"
        command << " --ab #{pab.join(',')}"
        command << " --aname \"#{paname.join('","')}\""
        command << " --audio-fallback faac"

        # subtitles
        subtitles.reject!{ |s| s.commentary? } if options.skipCommentaries
        psubtitle = []
        subtitles.each do |s|
          psubtitle << s.pos
        end
        command << " --subtitle #{psubtitle.join(',')}" if not psubtitle.empty?()
      end

      # title (useed by default and if preset is selected)
      command << " --title #{title.pos}"

      # the rest...
      command << " " << extra_arguments if not extra_arguments.nil?() and not extra_arguments.empty?
      if options.verbose
        command << " 2>&1"
      else
        command << " 2>#{Tools::OS::nullDevice()}"
      end

      converted.push(title.blocks())

      Tools::CON::warn "title #{title.pos} #{title.duration} #{title.size}"
      if not tracks.empty?
        Tools::CON::warn "audio-tracks"
        tracks.each do |t|
          Tools::CON::warn " - track #{t.pos}: #{t.descr}"
        end
      end
      if not subtitles.empty?
        Tools::CON::warn "subtitles"
        subtitles.each do |s|
          Tools::CON::warn " - track #{s.pos}: #{s.descr}"
        end
      end

      Tools::CON.info(command)
      if not options.debug
        parentDir = File.dirname(outputFile)
        FileUtils.mkdir_p(parentDir) unless File.directory?(parentDir)
        system command
        if File.exists?(outputFile)
          size = File.size(outputFile)
          if size >= 0 and size < (1 * 1024 * 1024)
            Tools::CON.warn("file-size only #{size / 1024} KB - removing file #{File.basename(outputFile)}")
            File.delete(outputFile)
            converted.delete(title.blocks())
          else
            Tools::CON.warn("file #{outputFile} created")
          end
        else
          Tools::CON.warn("file #{outputFile} not created")
        end
      end
    end
  end
end

class Chapter
  attr_accessor :pos, :cells, :blocks, :duration
  def initialize(pos)
    @pos = pos.to_i
    @duration = nil
    @cells = nil
    @blocks = nil
  end

  def to_s
    "#{pos}. #{duration} (cells=#{cells}, blocks=#{blocks})"
  end
end

class Subtitle
  attr_accessor :pos, :descr, :comment, :lang
  def initialize(pos, descr, lang)
    @pos = pos.to_i
    @lang = lang
    @descr = descr
    @comment = nil
  end

  def commentary?()
    return true if @descr.downcase().include?("commentary")
    return false
  end

  def to_s
    "#{pos}. #{descr} (lang=#{lang}, comment=#{comment}, commentary=#{commentary?()})"
  end
end

class AudioTrack
  attr_accessor :pos, :descr, :codec, :comment, :channels, :lang, :rate, :bitrate
  def initialize(pos, descr)
    @pos = pos.to_i
    @descr = descr
    @codec = nil
    @comment = nil
    @channels = nil
    @lang = nil
    @rate = nil
    @bitrate = nil
  end

  def commentary?()
    return true if @descr.downcase().include?("commentary")
    return false
  end

  def to_s
    "#{pos}. #{descr} (codec=#{codec}, channels=#{channels}, lang=#{lang}, comment=#{comment}, rate=#{rate}, bitrate=#{bitrate}, commentary=#{commentary?()})"
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
    @size = nil
    @fps = nil
    @duration = nil
    @mainFeature = false
  end

  def to_s
    "title #{"%02d" % pos}: #{duration}, #{size}, #{fps} fps, main-feature: #{mainFeature()}, blocks: #{blocks}, chapters: #{chapters.length}, audio-tracks: #{audioTracks.collect{|t| t.lang}.join(",")}, subtitles: #{subtitles.collect{|s| s.lang}.join(",")}"
  end
end

class MovieSource
  attr_accessor :title, :title_alt, :serial, :titles, :path
  def initialize(path)
    @titles = []
    @path = path
    @title = nil
    @title_alt = nil
    @serial = nil
  end

  def name(use_alt = false)
    return @title_alt if usable?(@title_alt) and use_alt
    return @title if usable?(@title)
    return File.basename(path()) if usable?(File.basename(path()))
    return "unknown"
  end

  def usable?(str)
    return false if str.nil?
    return false if str.strip.empty?
    return false if str.strip.eql? "unknown"
    return true
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
      s << "\n  chapters:"
      t.chapters().each do |c|
        s << "\n    #{c}"
      end
    end
    s
  end

  def to_s
    "#{path} (title=#{title}, title_alt=#{title_alt}, serial=#{serial}, name=#{name()})"
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
    m = (allowed().nil? or allowed().include?(value(obj))) 
    Tools::CON.debug("#{self.class().name()}: #{value(obj).inspect} is allowed (#{allowed.inspect()})? -> #{m}")
    return m
  end

  def filter(list, onlyFirst = false, skipDuplicatedValues = true)
    return list if allowed().nil?

    filtered = []
    stack = []
    allowed().each do |a|
      list.each do |e|
        v = value(e)
        if (v == a or v.eql? a) and (!skipDuplicatedValues or !stack.include?(v))
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
    return obj.pos
  end
end

class LangMatcher < ValueMatcher
  def value(obj)
    obj.lang
  end
end

def showUsageAndExit(options, msg = nil)
  puts options.to_s
  puts ""
  puts "available place-holders for output-file:"
  puts "  #pos#   - title-number on input-source"
  puts "  #size#  - resolution"
  puts "  #fps#   - frames per second"
  puts "  #ts#    - current timestamp"
  puts "  #title# - source-title (dvd-label, directory-basename, filename)"
  puts
  puts "hints:"
  puts "use raw disk devices (e.g. /dev/rdisk1) to ensure that libdvdnav can read the title"
  puts "see https://forum.handbrake.fr/viewtopic.php?f=10&t=26165&p=120036#p120035"
  puts
  puts "examples:"
  puts "convert main-feature with all original-tracks (audio and subtitle) for languages german and english"
  puts "#{File.basename($0)} --input /dev/rdisk1 --output \"~/Desktop/Movie.m4v\" --movie"
  puts
  puts "convert all episodes with all original-tracks (audio and subtitle) for languages german and english"
  puts "#{File.basename($0)} --input /dev/rdisk1 --output \"~/Desktop/Series_SeasonX_#pos#.m4v\" --episodes"
  puts
  puts "convert complete file or DVD with all tracks, languages etc."
  puts "#{File.basename($0)} --input /dev/rdisk1 --output \"~/Desktop/Output_#pos#.m4v\""
  puts
  if not msg.nil?
    puts msg
    puts
  end
  exit
end

options = Struct.new(
  :input, :output, :force,
  :ipodCompatibility, :enableAutocrop,
  :languages, :audioMixdown, :audioCopy,
  :audioEncoder, :audioEncoderMixdown, :audioEncoderBitrate,
  :maxHeight, :subtitles, :preset, :mainFeatureOnly, :titles, :chapters,
  :minLength, :maxLength, :skipDuplicates,
  :onlyFirstTrackPerLanguage, :skipCommentaries,
  :checkOnly, :xtra_args, :debug, :verbose,
  :x264profile, :x264preset, :x264tune).new

ARGV.options do |opts|
  opts.separator("")
  opts.separator("files")
  opts.on("--input INPUT", "input-source") { |arg| options.input = arg }
  opts.on("--output OUTPUT", "output-file (mp4, m4v and mkv supported)") { |arg| options.output = arg }
  opts.on("--force", "force override of existing files") { |arg| options.force = arg }
  opts.on("--check", "show only available titles and tracks") { |arg| options.checkOnly = arg }
  opts.on("--help", "Display this screen") { |arg| showUsageAndExit(opts.to_s) }

  opts.separator("")
  opts.separator("output-options")
  opts.on("--compatibility", "enables iPod compatible output (only m4v and mp4)") { |arg| options.ipodCompatibility = arg }
  opts.on("--autocrop", "automatically crop black bars") { |arg| options.enableAutocrop = arg }
  opts.on("--max-height HEIGTH", "maximum video height (e.g. 720, 1080)") { |arg| options.maxHeight = arg }
  opts.on("--audio LANGUAGES", Array, "the audio languages") { |arg| options.languages = arg }
  opts.on("--audio-mixdown", "add mixed down track (faac, Dolby ProLogic 2)") { |arg| options.audioMixdown = arg }
  opts.on("--audio-copy", "add original-audio track") { |arg| options.audioCopy = arg }
  opts.on("--audio-encoder ENCODER", "add encoded audio track (#{Handbrake::AUDIO_ENCODERS.join(', ')})") { |arg| options.audioEncoder = arg }
  opts.on("--audio-encoder-mixdown MIXDOWN", "mixdown encoded audio track (#{Handbrake::AUDIO_MIXDOWNS.join(', ')})") { |arg| options.audioEncoderMixdown = arg }
  opts.on("--audio-encoder-bitrate BITRATE", "bitrate for encoded audio track (default 160kb/s)") { |arg| options.audioEncoderBitrate = arg }
  opts.on("--subtitles LANGUAGES", Array, "the subtitle languages") { |arg| options.subtitles = arg }
  opts.on("--preset PRESET", "the handbrake-preset to use (#{Handbrake::getPresets().collect(){|p,s| p}.join(', ')})") { |arg| options.preset = arg }

  opts.separator("")
  opts.separator("filter-options")
  opts.on("--main", "main-feature only") { |arg| options.mainFeatureOnly = arg }
  opts.on("--titles TITLES", Array, "the title-numbers to convert (use --check to see available titles)") { |arg| options.titles = arg }
  opts.on("--chapters CHAPTERS", "the chapters to convert (e.g. 2 or 3-4)") { |arg| options.chapters = arg }
  opts.on("--min-length DURATION", "the minimum-track-length - format hh:nn:ss") { |arg| options.minLength = arg }
  opts.on("--max-length DURATION", "the maximum-track-length - format hh:nn:ss") { |arg| options.maxLength = arg }
  opts.on("--skip-duplicates", "skip duplicate titles (checks block-size)") { |arg| options.skipDuplicates = arg }
  opts.on("--only-first-track-per-language", "convert only first audio- or subtitle-track per language") { |arg| options.onlyFirstTrackPerLanguage = arg }
  opts.on("--skip-commentaries", "ignore commentary-audio- and subtitle-tracks") { |arg| options.skipCommentaries = arg }

  opts.separator("")
  opts.separator("expert-options")
  opts.on("--xtra ARGS", "additional arguments for handbrake") { |arg| options.xtra_args = arg }
  opts.on("--debug", "enable debug-mode (doesn't start conversion)") { |arg| options.debug = arg }
  opts.on("--verbose", "enable verbose output") { |arg| options.verbose = arg }
  opts.on("--x264-profile PRESET", "use x264-profile (#{Handbrake::X264_PROFILES.join(', ')})") { |arg| options.x264profile = arg }
  opts.on("--x264-preset PRESET", "use x264-preset (#{Handbrake::X264_PRESETS.join(', ')})") { |arg| options.x264preset = arg }
  opts.on("--x264-tune OPTION", "tune x264 (#{Handbrake::X264_TUNES.join(', ')})") { |arg| options.x264tune = arg }

  opts.separator("")
  opts.separator("shorts")
  opts.on("--default",   "sets: --audio deu,eng --subtitles deu,eng --audio-copy --skip-commentaries --only-first-track-per-language") do |arg|
    options.languages = ["deu", "eng"]
    options.subtitles = ["deu", "eng"]
    options.onlyFirstTrackPerLanguage = true
    options.audioCopy = true
    options.skipCommentaries = true
  end
  opts.on("--movie",   "sets: --default --main") do |arg|
    options.languages = ["deu", "eng"]
    options.subtitles = ["deu", "eng"]
    options.onlyFirstTrackPerLanguage = true
    options.audioCopy = true
    options.skipCommentaries = true
    options.mainFeatureOnly = true
  end
  opts.on("--episodes", "sets: --default --min-length 00:10:00 --max-length 00:50:00 --skip-duplicates") do |arg|
    options.languages = ["deu", "eng"]
    options.subtitles = ["deu", "eng"]
    options.onlyFirstTrackPerLanguage = true
    options.audioCopy = true
    options.skipCommentaries = true
    options.minLength = "00:10:00"
    options.maxLength = "00:50:00"
    options.skipDuplicates = true
  end
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

# set default values
options.force = false if options.force.nil?
options.ipodCompatibility = false if options.ipodCompatibility.nil?
options.enableAutocrop = false if options.enableAutocrop.nil?
options.audioCopy = true if options.audioMixdown.nil? and options.audioCopy.nil? and options.audioEncoder.nil?
options.mainFeatureOnly = false if options.mainFeatureOnly.nil?
options.skipDuplicates = false if options.skipDuplicates.nil?
options.onlyFirstTrackPerLanguage = false if options.onlyFirstTrackPerLanguage.nil?
options.skipCommentaries = false if options.skipCommentaries.nil?
options.checkOnly = false if options.checkOnly.nil?
options.debug = false if options.debug.nil?
options.verbose = false if options.verbose.nil?
options.titles.collect!{ |t| t.to_i } if not options.titles.nil?
options.audioEncoderBitrate = "160" if options.audioEncoderBitrate.nil?

if options.verbose and options.debug
  Tools::CON.level = Logger::DEBUG
elsif options.verbose or options.debug
  Tools::CON.level = Logger::INFO
else
  Tools::CON.level = Logger::WARN
end 

# check settings
showUsageAndExit(ARGV.options, "input not set") if options.input.nil?()
showUsageAndExit(ARGV.options, "output not set") if not options.checkOnly and options.output.nil?()
showUsageAndExit(ARGV.options, "\"#{options.input}\" does not exist") if not File.exists? options.input
showUsageAndExit(ARGV.options,"unknown x264-profile: #{options.x264profile}") if not options.x264profile.nil? and not Handbrake::X264_PROFILES.include?(options.x264profile)
showUsageAndExit(ARGV.options,"unknown x264-preset: #{options.x264preset}") if not options.x264preset.nil? and not Handbrake::X264_PRESETS.include?(options.x264preset)
showUsageAndExit(ARGV.options,"unknown x264-tune option: #{options.x264tune}") if not options.x264tune.nil? and not Handbrake::X264_TUNES.include?(options.x264tune)
showUsageAndExit(ARGV.options,"unknown audio-encoder: #{options.audioEncoder}") if not options.audioEncoder.nil? and not Handbrake::AUDIO_ENCODERS.include?(options.audioEncoder)
if options.audioEncoderMixdown.nil?
  options.audioEncoderMixdown = "auto"  
elsif not Handbrake::AUDIO_MIXDOWNS.include?(options.audioEncoderMixdown)
  showUsageAndExit(ARGV.options,"unknown mixdown-option: #{options.audioEncoderMixdown}")
end

if options.verbose and options.debug
  options.each_pair do |k,v|
    puts "#{k} = #{v.inspect}"
  end
end

titleMatcher = PosMatcher.new(options.titles)
audioMatcher = LangMatcher.new(options.languages)
subtitleMatcher = LangMatcher.new(options.subtitles)

Handbrake::convert(options, titleMatcher, audioMatcher, subtitleMatcher)