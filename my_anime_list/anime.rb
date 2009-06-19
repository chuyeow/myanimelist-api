require 'curb'
require 'nokogiri'

module MyAnimeList

  module Rack
    module Auth

      def auth
        @auth ||= Rack::Auth::Basic::Request.new(request.env)
      end

      def unauthenticated!(realm = 'myanimelist.net')
        headers['WWW-Authenticate'] = %(Basic realm="#{realm}")
        throw :halt, [ 401, 'Authorization Required' ]
      end

      def bad_request!
        throw :halt, [ 400, 'Bad Request' ]
      end

      def authenticated?
        request.env['REMOTE_USER']
      end

      # Authenticate with MyAnimeList.net.
      def authenticate_with_mal(username, password)

        curl = Curl::Easy.new('http://myanimelist.net/login.php')

        authenticated = false
        cookies = []
        curl.on_header { |header|

          # Parse cookies from the headers (yes, this is a naive implementation but it's fast).
          cookies << "#{$1}=#{$2}" if header =~ /^Set-Cookie: ([^=])=([^;]+;)/

          # A HTTP 302 redirection to the MAL panel indicates successful authentication.
          authenticated = true if header =~ %r{^Location: http://myanimelist.net/panel.php\s+}

          header.length
        }
        curl.http_post(
          Curl::PostField.content('username', username),
          Curl::PostField.content('password', password),
          Curl::PostField.content('cookies', '1')
        )

        # Reset the on_header handler.
        curl.on_header

        # Save cookie string into session.
        session['cookie_string'] = cookies.join(' ') if authenticated

        authenticated
      end

      def authenticate
        return if authenticated?
        unauthenticated! unless auth.provided?
        bad_request! unless auth.basic?
        unauthenticated! unless authenticate_with_mal(*auth.credentials)
        request.env['REMOTE_USER'] = auth.username
      end
    end # END module Auth
  end # END module Rack


  class Anime
    attr_accessor :id, :title, :rank, :popularity_rank, :image_url, :type, :episodes, :status, :classification,
                  :members_score, :members_count, :favorited_count
    attr_writer :other_titles, :genres

    # These attributes are specific to a user-anime pair, probably should go into another model.
    attr_accessor :watched_episodes, :score, :watched_status

    # Scrape anime details page on MyAnimeList.net. Very fragile!
    def self.scrape_anime(id, cookie_string = nil)
      curl = Curl::Easy.new("http://myanimelist.net/anime/#{id}")
      curl.cookies = cookie_string if cookie_string
      curl.perform

      response = curl.body_str

      doc = Nokogiri::HTML(response)

      anime = Anime.new
      anime.id = id

      # Title and rank.
      # Example:
      # <h1><div style="float: right; font-size: 13px;">Ranked #96</div>Lucky ☆ Star</h1>
      anime.title = doc.at(:h1).children.find { |o| o.text? }.to_s
      anime.rank = doc.at('h1 > div').text.gsub(/\D/, '').to_i

      if image_node = doc.at('div#rightcontent a img')
        anime.image_url = image_node['src']
      end

      # Extract from sections on the right column: Alternative Titles, Information, Statistics, Popular Tags.

      # Alternative Titles section.
      # Example:
      # <h2>Alternative Titles</h2>
      # <div class="spaceit_pad"><span class="dark_text">English:</span> Lucky Star/div>
      # <div class="spaceit_pad"><span class="dark_text">Synonyms:</span> Lucky Star, Raki ☆ Suta</div>
      # <div class="spaceit_pad"><span class="dark_text">Japanese:</span> らき すた</div>
      right_column_nodeset = doc.xpath('//div[@id="rightcontent"]/table/tr/td[@class="borderClass"]')

      if (node = right_column_nodeset.at('//span[text()="English:"]')) && node.next
        anime.other_titles[:english] = node.next.text.strip
      end
      if (node = right_column_nodeset.at('//span[text()="Synonyms:"]')) && node.next
        anime.other_titles[:synonyms] = node.next.text.strip
      end
      if (node = right_column_nodeset.at('//span[text()="Japanese:"]')) && node.next
        anime.other_titles[:japanese] = node.next.text.strip
      end

      # Information section.
      # Example:
      # <h2>Information</h2>
      # <div><span class="dark_text">Type:</span> TV</div>
      # <div class="spaceit"><span class="dark_text">Episodes:</span> 24</div>
      # <div><span class="dark_text">Status:</span> Finished Airing</div>
      # <div class="spaceit"><span class="dark_text">Aired:</span> Apr  9, 2007 to Sep  17, 2007</div>
      # <div>
      #   <span class="dark_text">Producers:</span>
      #   <a href="http://myanimelist.net/anime.php?p=2">Kyoto Animation</a>,
      #   <a href="http://myanimelist.net/anime.php?p=104">Lantis</a>,
      #   <a href="http://myanimelist.net/anime.php?p=262">Kadokawa Pictures USA</a><sup><small>L</small></sup>,
      #   <a href="http://myanimelist.net/anime.php?p=286">Bang Zoom! Entertainment</a>
      # </div>
      # <div class="spaceit">
      #   <span class="dark_text">Genres:</span>
      #   <a href="http://myanimelist.net/anime.php?genre[]=4">Comedy</a>,
      #   <a href="http://myanimelist.net/anime.php?genre[]=20">Parody</a>,
      #   <a href="http://myanimelist.net/anime.php?genre[]=23">School</a>,
      #   <a href="http://myanimelist.net/anime.php?genre[]=36">Slice of Life</a>
      # </div>
      # <div><span class="dark_text">Duration:</span> 24 min. per episode</div>
      # <div class="spaceit"><span class="dark_text">Rating:</span> PG-13 - Teens 13 or older</div>
      if (node = right_column_nodeset.at('//span[text()="Type:"]')) && node.next
        anime.type = node.next.text.strip
      end
      if (node = right_column_nodeset.at('//span[text()="Episodes:"]')) && node.next
        anime.episodes = node.next.text.strip.gsub(',', '').to_i
      end
      if (node = right_column_nodeset.at('//span[text()="Status:"]')) && node.next
        anime.status = node.next.text.strip
      end
      if node = right_column_nodeset.at('//span[text()="Genres:"]')
        node.parent.search('a').each do |a|
          anime.genres << a.text.strip
        end
      end
      if (node = right_column_nodeset.at('//span[text()="Rating:"]')) && node.next
        anime.classification = node.next.text.strip
      end

      # Statistics
      # Example:
      # <h2>Statistics</h2>
      # <div>
      #   <span class="dark_text">Score:</span> 8.41<sup><small>1</small></sup>
      #   <small>(scored by 22601 users)</small>
      # </div>
      # <div class="spaceit"><span class="dark_text">Ranked:</span> #96<sup><small>2</small></sup></div>
      # <div><span class="dark_text">Popularity:</span> #15</div>
      # <div class="spaceit"><span class="dark_text">Members:</span> 36,961</div>
      # <div><span class="dark_text">Favorites:</span> 2,874</div>
      if (node = right_column_nodeset.at('//span[text()="Score:"]')) && node.next
        anime.members_score = node.next.text.strip.to_f
      end
      if (node = right_column_nodeset.at('//span[text()="Popularity:"]')) && node.next
        anime.popularity_rank = node.next.text.strip.sub('#', '').gsub(',', '').to_i
      end
      if (node = right_column_nodeset.at('//span[text()="Members:"]')) && node.next
        anime.members_count = node.next.text.strip.gsub(',', '').to_i
      end
      if (node = right_column_nodeset.at('//span[text()="Favorites:"]')) && node.next
        anime.favorited_count = node.next.text.strip.gsub(',', '').to_i
      end

      anime
    end

    def other_titles
      @other_titles ||= {}
    end

    def genres
      @genres ||= []
    end

    def to_json
      {
        :id => id,
        :title => title,
        :other_titles => other_titles,
        :type => type,
        :rank => rank,
        :popularity_rank => popularity_rank,
        :episodes => episodes,
        :status => status,
        :genres => genres,
        :classification => classification,
        :members_score => members_score,
        :members_count => members_count,
        :favorited_count => favorited_count,
        :watched_episodes => watched_episodes,
        :score => score,
        :watched_status => watched_status,
      }.to_json
    end
  end # END class Anime

end