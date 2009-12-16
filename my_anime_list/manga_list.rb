module MyAnimeList
  class MangaList

    def self.manga_list_of(username)
      curl = Curl::Easy.new("http://myanimelist.net/mangalist/#{username}")
      curl.headers['User-Agent'] = 'MyAnimeList Unofficial API (http://mal-api.com/)'
      begin
        curl.perform
      rescue Exception => e
        raise NetworkError("Network error getting manga list for '#{username}'. Original exception: #{e.message}.", e)
      end

      raise NetworkError("Network error getting manga list for '#{username}'. MyAnimeList returned HTTP status code #{curl.response_code}.", e) unless curl.response_code == 200

      response = curl.body_str

      manga_list = MangaList.new

      # HTML scraping hell begins.
      doc = Nokogiri::HTML(response)


      manga_list
    end

    def manga
      @manga ||= []
    end

    def to_json
      {
        :manga => manga
      }.to_json
    end

    def to_xml
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct!

      xml.mangalist do |xml|
        manga.each do |a|
          xml << a.to_xml(:skip_instruct => true)
        end
      end
    end

  end # END class MangaList
end