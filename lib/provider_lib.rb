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
      "name" => "#{name}",
      "season" => "%02d" % season,
      "episode" => "%02d" % episode,
      "title" => "#{title_de}",
      "title_en" => "#{title_en}",
      "descr" => "#{descr}"
    }
  end
end

class AbstractInfoProvider
  require 'rubygems'
  require 'hpricot'
  require 'open-uri'
  require 'iconv'

  #USER_AGENT = 'Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; en-US; rv:1.9.1.2) Gecko/20090729 Firefox/3.5.2'
  if Tools::OS::windows?()
    USER_AGENT = 'Mozilla/5.0 (Windows; U; Windows NT 5.1; de; rv:1.8.0.1) Gecko/20060111 Firefox/1.5.0.1'
  else
    USER_AGENT = 'Mozilla/5.0 (X11; U; Linux i686; de-DE; rv:1.7.3) Gecko/20040924 Epiphany/1.4.4 (Ubuntu)'
  end
  
  def load(identifier, season, episode)
    raise "unimplemented yet"
  end
  
  def loadUrl(url)
    content = open(url, 'User-Agent' => USER_AGENT).read
    content.gsub!(/&Ouml;/, "Ö")
    content.gsub!(/&ouml;/, "ö")
    content.gsub!(/&auml;/, "ä")
    content.gsub!(/&uuml;/, "ü")
    content.gsub!(/&szlig;/, "ß")
    doc = Hpricot(content)
    return doc
  end
  
  def str(value)
    return nil if value.nil? or value.strip.empty?
    if Tools::OS::windows?
      begin
        v = Iconv.iconv('iso-8859-15', 'utf-8', value).first
      rescue => e
        v = value
      end
      value = v
    end
    return value.strip
  end
end

class Serienjunkies < AbstractInfoProvider

  URL = 'http://www.serienjunkies.de'
  
  def load(serienjunkies_id, season, episode)
    e = "%dx%02d" % [season, episode]
    url = URL + '/' + serienjunkies_id + '/alle-serien-staffeln.html'
    doc = loadUrl(url)

    name = doc.search("//*[@id='.C3.9Cbersicht']/a").innerHTML
    info = TagData.new(name, season, episode)
    table = doc.search("table[@class=eplist]")
    elements = table.search("td[text()='#{e}']")
  
    raise "found no info for #{serienjunkies_id} episode #{e} at #{url}" if elements.nil? or elements.empty?

    elements.each do |td|
      tr = td.parent
      data = tr.search("td")
      raise "found not info for #{e} at #{url}" if data.size() < 4
      links = data[2].search("a")
      info.title_en = str(links[0].innerText()) unless links.empty? 

      links = data[3].search("a")
      info.title_de = str(links[0].innerText()) unless links.empty?
      
      if not links.empty?
        descr_link = links[0].get_attribute("href") 
        info.sj_url = str(URL + descr_link)
        info.descr = descr(URL + descr_link)
      end
    end
    return info
  end

  def descr(url)
    doc = loadUrl(url)
    raise "can not load #{url}" if doc.nil?
    table = doc.search("table[@id=epdetails]")
    summary_span = table.at("//span[@class=summary]")
    
    return nil if summary_span.nil? or summary_span.following_siblings.nil? or summary_span.following_siblings.empty?

    return str(summary_span.following_siblings.first.innerText())
  end
end