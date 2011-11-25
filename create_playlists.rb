class Tags
  require 'lib/mp4info'
  attr_accessor :artist, :title, :time, :track, :disc, :comment, :seconds
  
  def to_s
    s = ""
    vars = instance_variables.sort
    instance_variables.each do |v|
      s << ", " if not s.empty?
      s << "#{v}=#{eval(v)}"
    end
    s
  end
  
  def self.read(file)
    info = MP4Info.open(file)
    t = Tags.new
    t.artist = info.ART
    t.title = info.NAM
    t.time = info.TIME
    t.seconds = info.SECS
    tmp = info.DISK
    t.disc = tmp[0] if tmp
    tmp = info.TRKN
    t.track = tmp[0] if tmp
    t.comment = info.CMT
    return t
  end
end

class Playlist
  @data = nil
  def initialize()
    @data = ""
  end

  def add(file, tag)
    raise "unsupported operation"
  end

  def ext()
    raise "unsupported operation"
  end
  
  def persist(file)
    File.open(file, "w") { |f|
      f << data()
    }
  end
  
  def header()
    ""
  end
  
  def data()
    header() + @data + footer()
  end
  
  def footer()
    ""
  end

  def to_s
    data()
  end
  
  def line(line)
    @data << "#{line}\n"
  end
end

class M3UPlaylist < Playlist
  def add(file, tag)
    line(file)
  end
  def ext()
    "_simple.m3u"
  end
end

class ExtM3UPlaylist < Playlist
  def add(file, tag)
    line("#EXTINF:#{tag.seconds},#{tag.title}")
    line(file)
  end
  
  def header()
    ""#EXTM3U"
  end

  def ext()
    ".m3u"
  end
end

class PLSPlaylist < Playlist
  @count = nil
  def initialize()
    super()
    @count = 0
  end

  def add(file, tag)
    @count += 1
    line("File#{@count}=#{file}")
    line("Title#{@count}=#{tag.title}")
    line("Length#{@count}=#{tag.seconds}")
    line("")
  end

  def header()
    "[playlist]"
  end
  
  def footer()
    "NumberOfEntries=#{@count}\nVersion=2"
  end
  
  def ext()
    ".pls"
  end
end

class XSPFPlaylist < Playlist
  require 'uri'
  def add(file, tag)
    line("        <track>")
    line("            <location>file://#{URI::escape(file)}</location>")
    line("            <title>#{tag.title}</title>")
    line("            <creator>#{tag.artist}</creator>")
    line("            <trackNum>#{tag.track}</trackNum>")
    line("            <duration>#{tag.seconds}</duration>")
    line("        </track>")
  end

  def header()
    s = "<playlist version=\"2\">"
    s << "\n"
    s << "    <title>Wiedergabeliste</title>"
    s << "\n"
    s << "    <trackList>"
    s << "\n"
    s
  end
  
  def footer()
    s = "    </trackList>"
    s << "\n"
    s << "</playlist>"
    s << "\n"
    s
  end

  def ext()
    ".xspf"
  end
end

class PlaylistMgr
  private

  @@playlists = {}
  @@tagCache = {}
  
  public

  def self.registerDefaults()
    register(:M3U, M3UPlaylist)
    register(:EXTM3U, ExtM3UPlaylist)
    register(:PLS, PLSPlaylist)
    register(:XSPF, XSPFPlaylist)
    self
  end

  def self.register(key, playlist)
    raise "there is already a playlist registered for key #{key}" if @@playlists.has_key?(key)
    @@playlists[key] = playlist
    self
  end

  def self.create(dir, options = {:M3U => true })
    dir = File.expand_path(dir)
    dirname = File.basename(dir)
  
    pl = []
    options.each do |k,v|
      pl << @@playlists[k].new() if v 
    end
    return if pl.length() == 0
  
    ## current directory
    files = Dir["#{dir}/**/*.mp4"]
    idx = 0 
    files.each do |mp4|
      idx += 1
      ## puts "#{mp4} (#{idx}/#{files.size()})"
      mp4r = mp4[dir.length + 1, mp4.length - dir.length] if mp4.start_with? dir
      ## cache value - maybe we need it later because of recursion 
      @@tagCache[mp4] = Tags.read(mp4) unless @@tagCache.has_key?(mp4)
      t = @@tagCache[mp4]
      pl.each do |l|
        l.add(mp4r, t)
      end
    end
    pl.each do |l|
      file = File.join(dir, "#{dirname}#{l.ext()}")
      puts "writing #{file}..."
      l.persist(file)
    end
    ## subdirectories
    Dir.entries(dir).each do |e|
      next if e.eql?(".") or e.eql?("..")
      sub = File.join(dir, e)
      next unless File.directory?(sub)
      create(sub, options)
    end
    self
  end
end

def usage(msg = nil)
  puts "usage: $0 <movie-dir>"
  if msg
    puts
    puts msg
  end
  puts
end

dir = ARGV[0]
if not dir
  usage
  exit 
end
dir = File.expand_path(dir)
if not File.exists?(dir)
  usage "#{dir} does not exists"
  exit
end

PlaylistMgr::registerDefaults()
PlaylistMgr::create(dir, {:M3U => true, :EXTM3U => true, :PLS => true, :XSPF => true}) 
