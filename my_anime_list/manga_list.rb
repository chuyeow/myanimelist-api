module MyAnimeList
  class MangaList
    attr_writer :manga

    def self.manga_list_of(username)
      curl = Curl::Easy.new("http://myanimelist.net/malappinfo.php?u=#{username}&status=all&type=manga")
      curl.headers['User-Agent'] = ENV['USER_AGENT']
      begin
        curl.perform
      rescue Exception => e
        raise NetworkError("Network error getting manga list for '#{username}'. Original exception: #{e.message}.", e)
      end

      raise NetworkError("Network error getting manga list for '#{username}'. MyAnimeList returned HTTP status code #{curl.response_code}.", e) unless curl.response_code == 200

      response = curl.body_str

      # Check for usernames that don't exist. malappinfo.php returns a simple "Invalid username" string (but doesn't
      # return a 404 status code).
      throw :halt, [404, 'User not found'] if response =~ /^invalid username/i

      xml_doc = Nokogiri::XML.parse(response)

      manga_list = MangaList.new

      # Parse manga.
      manga_list.manga = xml_doc.search('manga').map do |manga_node|
        manga = MyAnimeList::Manga.new
        manga.id                = manga_node.at('series_mangadb_id').text.to_i
        manga.title             = manga_node.at('series_title').text
        manga.type              = manga_node.at('series_type').text
        manga.status            = manga_node.at('series_status').text
        manga.chapters          = manga_node.at('series_chapters').text.to_i
        manga.volumes           = manga_node.at('series_volumes').text.to_i
        manga.image_url         = manga_node.at('series_image').text
        manga.listed_manga_id   = manga_node.at('my_id').text.to_i
        manga.volumes_read      = manga_node.at('my_read_volumes').text.to_i
        manga.chapters_read     = manga_node.at('my_read_chapters').text.to_i
        manga.score             = manga_node.at('my_score').text.to_i
        manga.read_status       = manga_node.at('my_status').text

        manga
      end

      # Parse statistics.
      manga_list.statistics[:days] = xml_doc.at('myinfo user_days_spent_watching').text.to_f

      manga_list
    end

    def manga
      @manga ||= []
    end

    def statistics
      @statistics ||= {}
    end

    def to_json(*args)
      {
        :manga => manga,
        :statistics => statistics
      }.to_json(*args)
    end

    def to_xml
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct!

      xml.mangalist do |xml|
        manga.each do |a|
          xml << a.to_xml(:skip_instruct => true)
        end

        xml.statistics do |xml|
          xml.days statistics[:days]
        end
      end
    end

  end # END class MangaList
end
