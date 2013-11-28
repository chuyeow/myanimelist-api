require 'chronic'

module MyAnimeList
  class User
    attr_accessor :username

    # Returns a user's history.
    #
    # Options:
    #  * type - Set to :anime or :manga to return only anime or manga history respectively. Otherwise, both anime and
    #           manga history are returned.
    def history(options = {})

      history_url = case options[:type]
      when :anime
        "http://myanimelist.net/history/#{username}/anime"
      when :manga
        "http://myanimelist.net/history/#{username}/manga"
      else
        "http://myanimelist.net/history/#{username}"
      end

      curl = Curl::Easy.new(history_url)
      curl.headers['User-Agent'] = ENV['USER_AGENT']
      begin
        curl.perform
      rescue Exception => e
        raise MyAnimeList::NetworkError.new("Network error getting history for username=#{username}. Original exception: #{e.message}.", e)
      end

      response = curl.body_str

      doc = Nokogiri::HTML(response)

      results = []
      doc.search('div#content table tr').each do |tr|
        cells = tr.search('td')
        next unless cells && cells.size == 2

        link = cells[0].at('a')
        anime_id = link['href'][%r{http://myanimelist.net/anime.php\?id=(\d+)}, 1]
        anime_id = link['href'][%r{http://myanimelist.net/anime/(\d+)/?.*}, 1] unless anime_id
        anime_id = anime_id.to_i

        manga_id = link['href'][%r{http://myanimelist.net/manga.php\?id=(\d+)}, 1]
        manga_id = link['href'][%r{http://myanimelist.net/manga/(\d+)/?.*}, 1] unless manga_id
        manga_id = manga_id.to_i

        title = link.text.strip
        episode_or_chapter = cells[0].at('strong').text.to_i
        time_string = cells[1].text.strip

        begin
          # FIXME The datetime is in the user's timezone set in his profile http://myanimelist.net/editprofile.php.
          datetime = DateTime.strptime(time_string, '%m-%d-%y, %H:%M %p')
          time = Time.utc(datetime.year, datetime.month, datetime.day, datetime.hour, datetime.min, datetime.sec)
        rescue ArgumentError
          time = Chronic.parse(time_string)
        end

        # Constructs either an anime object, or manga object
        # based on the presence of either id.
        results << Hash.new.tap do |history_entry|
          history_entry[:anime_id] = anime_id if anime_id > 0
          history_entry[:episode] = episode_or_chapter if anime_id > 0
          history_entry[:manga_id] = manga_id if manga_id > 0
          history_entry[:chapter] = episode_or_chapter if manga_id > 0
          history_entry[:title] = title
          history_entry[:time] = time
        end
      end

      results
    rescue Exception => e
      raise MyAnimeList::UnknownError.new("Error getting history for username=#{username}. Original exception: #{e.message}.", e)
    end


    def profile
      profile_url = "http://myanimelist.net/profile/#{username}"
      curl = Curl::Easy.new(profile_url)
      curl.headers['User-Agent'] = ENV['USER_AGENT']
      begin
        curl.perform
      rescue Exception => e
        raise MyAnimeList::NetworkError.new("Network error getting profile details for username=#{username}. Original exception: #{e.message}.", e)
      end

      response = curl.body_str

      doc = Nokogiri::HTML(response)

      left_content = doc.at("#content .profile_leftcell")
      avatar = left_content.at("#profileRows").previous_element.at("img")

      main_content = doc.at('#content #horiznav_nav').next_element
      details, updates, anime_stats, manga_stats = main_content.search("> table table")

      {
        :avatar_url => avatar['src'],
        :details => UserDetails.parse(details),
        :anime_stats => UserStats.parse(anime_stats),
        :manga_stats => UserStats.parse(manga_stats),
      }
    rescue Exception => e
      raise MyAnimeList::UnknownError.new("Error getting history for username=#{username}. Original exception: #{e.message}.", e)
    end

    class UserDetails
      def self.parse(node)
        result = {}
        node.search("tr").each do |tr|
          label, value = tr.search("> td")
          parameterized_label = label.text.downcase.gsub(/\s+/, "_")
          result[parameterized_label] = case parameterized_label
          when "anime_list_views", "manga_list_views", "comments"
            parse_integer(value.text)
          when "forum_posts"
            parse_integer(value.text.match(/^[,0-9]+/)[0])
          when "website"
            value.at("a")['href']
          else
            value.text
          end
        end
        add_defaults(result)
      end

      def self.parse_integer(integer_string)
        integer_string.gsub(",", "").to_i
      end

      def self.add_defaults(result)
        # Default values for details that are not necessarily visible
        {
          "birthday" => nil,
          "location" => nil,
          "website" => nil,
          "aim" => nil,
          "msn" => nil,
          "yahoo" => nil,
          "comments" => 0,
          "forum_posts" => 0,
        }.merge(result)
      end
    end

    class UserStats
      def self.parse(node)
        result = {}
        node.search("tr").each do |tr|
          label, value, _ = tr.search("td")
          parameterized_label = label.text.downcase.gsub(/[\(\)]/, "").gsub(/\s+/, "_")
          result[parameterized_label] = value.text.to_f
        end
        result
      end
    end

  end
end
