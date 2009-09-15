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
      curl.headers['User-Agent'] = 'MyAnimeList Unofficial API (http://mal-api.com/)'
      begin
        curl.perform
      rescue Exception => e
        raise MyAnimeList::NetworkError.new("Network error getting history for username=#{username}. Original exception: #{e.message}.", e)
      end

      response = curl.body_str

      doc = Nokogiri::HTML(response)

      results = []
      doc.search('div#rightcontent_nopad table tr').each do |tr|
        cells = tr.search('td')
        next unless cells && cells.size == 2

        link = cells[0].at('a')
        anime_id = link['href'][%r{http://myanimelist.net/anime.php\?id=(\d+)}, 1]
        anime_id = link['href'][%r{http://myanimelist.net/anime/(\d+)/?.*}, 1] unless anime_id
        anime_id = anime_id.to_i

        title = link.text.strip
        episode = cells[0].at('strong').text.to_i
        time_string = cells[1].text.strip

        begin
          # FIXME The datetime is in the user's timezone set in his profile http://myanimelist.net/editprofile.php.
          datetime = DateTime.strptime(time_string, '%m-%d-%y, %H:%M %p')
          time = Time.utc(datetime.year, datetime.month, datetime.day, datetime.hour, datetime.min, datetime.sec)
        rescue ArgumentError
          time = Chronic.parse(time_string)
        end


        results << {
          :anime_id => anime_id,
          :title => title,
          :episode => episode,
          :time => time
        }

      end

      results

    rescue Exception => e
      raise MyAnimeList::UnknownError.new("Error getting history for username=#{username}. Original exception: #{e.message}.", e)
    end
  end
end