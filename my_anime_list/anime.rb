require 'curb'
require 'nokogiri'

module MyAnimeList

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


  class Anime
    attr_accessor :id, :title, :rank, :image_url, :type, :episodes
    attr_writer :other_titles

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

      # Example:
      # <h1><div style="float: right; font-size: 13px;">Ranked #96</div>Lucky ☆ Star</h1>
      anime.title = doc.at(:h1).children.find { |o| o.text? }.to_s
      anime.rank = doc.at('h1 > div').text.gsub(/\D/, '')

      if image_node = doc.at('div#rightcontent a img')
        anime.image_url = image_node['src']
      end

      # The sections on the right column with the Alternative Titles, Information, Statistics, Popular Tags.
      doc.css('div#rightcontent table tr td.borderClass > h2').each do |header|
        case header.text
        when 'Alternative Titles'

          # Example:
          # <h2>Alternative Titles</h2>
          # <div class="spaceit_pad"><span class="dark_text">English:</span> Lucky Star/div>
          # <div class="spaceit_pad"><span class="dark_text">Synonyms:</span> Lucky Star, Raki ☆ Suta</div>
          # <div class="spaceit_pad"><span class="dark_text">Japanese:</span> らき すた</div>
          sibling = header.next
          while sibling && sibling.name == 'div'
            span_node = sibling.at(:span)
            case span_node.text
            when 'English:'
              anime.other_titles[:english] = span_node.next.text.strip
            when 'Synonyms:'
              anime.other_titles[:synonyms] = span_node.next.text.strip
            when 'Japanese:'
              anime.other_titles[:japanese] = span_node.next.text.strip
            end

            sibling = sibling.next
          end

        when 'Information'

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
          #  </div>
          #  <div><span class="dark_text">Duration:</span> 24 min. per episode</div>
          #  <div class="spaceit"><span class="dark_text">Rating:</span> PG-13 - Teens 13 or older</div>

        when 'Statistics'
        when 'My Info'
        when 'Popular Tags'
        end
      end



      anime
    end

    def other_titles
      @other_titles ||= {}
    end

    def to_json
      {
        :id => id,
        :title => title,
        :other_titles => other_titles,
        :type => type,
        :episodes => episodes,
        :watched_episodes => watched_episodes,
        :score => score,
        :watched_status => watched_status,
      }.to_json
    end
  end # END class Anime

end