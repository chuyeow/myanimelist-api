module MyAnimeList
  class AnimeList
    attr_writer :anime

    # FIXME This should return an AnimeList instance.
    def self.anime_list_of(username)
      curl = Curl::Easy.new("http://myanimelist.net/malappinfo.php?u=#{username}&status=all")
      curl.headers['User-Agent'] = 'MyAnimeList Unofficial API (http://mal-api.com/)'
      begin
        curl.perform
      rescue Exception => e
        raise NetworkError("Network error getting anime list for '#{username}'. Original exception: #{e.message}.", e)
      end

      raise NetworkError("Network error getting anime list for '#{username}'. MyAnimeList returned HTTP status code #{curl.response_code}.", e) unless curl.response_code == 200

      response = curl.body_str

      # Check for usernames that don't exist. malappinfo.php returns a simple "Invalid username" string (but doesn't
      # return a 404 status code).
      throw :halt, [404, 'User not found'] if response =~ /^invalid username/i

      xml_doc = Nokogiri::XML.parse(response)

      anime_list = AnimeList.new

      anime_list.anime = xml_doc.search('anime').map do |anime_node|
        anime = MyAnimeList::Anime.new
        anime.id                = anime_node.at('series_animedb_id').text.to_i
        anime.title             = anime_node.at('series_title').text
        anime.type              = anime_node.at('series_type').text
        anime.status            = anime_node.at('series_status').text
        anime.episodes          = anime_node.at('series_episodes').text.to_i
        anime.watched_episodes  = anime_node.at('my_watched_episodes').text.to_i
        anime.score             = anime_node.at('my_score').text
        anime.watched_status    = anime_node.at('my_status').text

        anime
      end

      anime_list
    end

    def anime
      @anime ||= []
    end

    def statistics
      @statistics ||= {}
    end

    def to_json
      {
        :anime => anime,
        :statistics => statistics
      }.to_json
    end
  end
end