require 'curb'
require 'nokogiri'

module MyAnimeList

  module Rack
    module Auth

      def auth
        @auth ||= ::Rack::Auth::Basic::Request.new(request.env)
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
                  :members_score, :members_count, :favorited_count, :synopsis
    attr_writer :other_titles, :genres, :tags, :manga_adaptations, :prequels, :sequels, :side_stories

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

      # -
      # Extract from sections on the left column: Alternative Titles, Information, Statistics, Popular Tags.
      # -

      # Alternative Titles section.
      # Example:
      # <h2>Alternative Titles</h2>
      # <div class="spaceit_pad"><span class="dark_text">English:</span> Lucky Star/div>
      # <div class="spaceit_pad"><span class="dark_text">Synonyms:</span> Lucky Star, Raki ☆ Suta</div>
      # <div class="spaceit_pad"><span class="dark_text">Japanese:</span> らき すた</div>
      left_column_nodeset = doc.xpath('//div[@id="rightcontent"]/table/tr/td[@class="borderClass"]')

      if (node = left_column_nodeset.at('//span[text()="English:"]')) && node.next
        anime.other_titles[:english] = node.next.text.strip
      end
      if (node = left_column_nodeset.at('//span[text()="Synonyms:"]')) && node.next
        anime.other_titles[:synonyms] = node.next.text.strip
      end
      if (node = left_column_nodeset.at('//span[text()="Japanese:"]')) && node.next
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
      if (node = left_column_nodeset.at('//span[text()="Type:"]')) && node.next
        anime.type = node.next.text.strip
      end
      if (node = left_column_nodeset.at('//span[text()="Episodes:"]')) && node.next
        anime.episodes = node.next.text.strip.gsub(',', '').to_i
      end
      if (node = left_column_nodeset.at('//span[text()="Status:"]')) && node.next
        anime.status = node.next.text.strip
      end
      if node = left_column_nodeset.at('//span[text()="Genres:"]')
        node.parent.search('a').each do |a|
          anime.genres << a.text.strip
        end
      end
      if (node = left_column_nodeset.at('//span[text()="Rating:"]')) && node.next
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
      if (node = left_column_nodeset.at('//span[text()="Score:"]')) && node.next
        anime.members_score = node.next.text.strip.to_f
      end
      if (node = left_column_nodeset.at('//span[text()="Popularity:"]')) && node.next
        anime.popularity_rank = node.next.text.strip.sub('#', '').gsub(',', '').to_i
      end
      if (node = left_column_nodeset.at('//span[text()="Members:"]')) && node.next
        anime.members_count = node.next.text.strip.gsub(',', '').to_i
      end
      if (node = left_column_nodeset.at('//span[text()="Favorites:"]')) && node.next
        anime.favorited_count = node.next.text.strip.gsub(',', '').to_i
      end

      # Popular Tags
      # Example:
      # <h2>Popular Tags</h2>
      # <span style="font-size: 11px;">
      #   <a href="http://myanimelist.net/anime.php?tag=comedy" style="font-size: 24px" title="1059 people tagged with comedy">comedy</a>
      #   <a href="http://myanimelist.net/anime.php?tag=parody" style="font-size: 11px" title="493 people tagged with parody">parody</a>
      #   <a href="http://myanimelist.net/anime.php?tag=school" style="font-size: 12px" title="546 people tagged with school">school</a>
      #   <a href="http://myanimelist.net/anime.php?tag=slice of life" style="font-size: 18px" title="799 people tagged with slice of life">slice of life</a>
      # </span>
      if (node = left_column_nodeset.at('//span[preceding-sibling::h2[text()="Popular Tags"]]'))
        node.search('a').each do |a|
          anime.tags << a.text
        end
      end


      # -
      # Extract from sections on the right column: Synopsis, Related Anime, Characters & Voice Actors, Reviews
      # Recommendations.
      # -
      right_column_nodeset = doc.xpath('//div[@id="rightcontent"]/table/tr/td/div/table')

      # Synopsis
      # Example:
      # <td>
      # <h2>Synopsis</h2>
      # Having fun in school, doing homework together, cooking and eating, playing videogames, watching anime. All those little things make up the daily life of the anime- and chocolate-loving Izumi Konata and her friends. Sometimes relaxing but more than often simply funny! <br />
      # -From AniDB
      synopsis_h2 = right_column_nodeset.at('//h2[text()="Synopsis"]')
      if synopsis_h2
        node = synopsis_h2.next
        while node
          if anime.synopsis
            anime.synopsis << node.to_s 
          else
            anime.synopsis = node.to_s
          end

          node = node.next
        end
      end

      # Related Anime
      # Example:
      # <td>
      #   <br>
      #   <h2>Related Anime</h2>
      #   Adaptation: <a href="http://myanimelist.net/manga/9548/Higurashi_no_Naku_Koro_ni_Kai_Minagoroshi-hen">Higurashi no Naku Koro ni Kai Minagoroshi-hen</a>,
      #   <a href="http://myanimelist.net/manga/9738/Higurashi_no_Naku_Koro_ni_Matsuribayashi-hen">Higurashi no Naku Koro ni Matsuribayashi-hen</a><br>
      #   Prequel: <a href="http://myanimelist.net/anime/934/Higurashi_no_Naku_Koro_ni">Higurashi no Naku Koro ni</a><br>
      #   Sequel: <a href="http://myanimelist.net/anime/3652/Higurashi_no_Naku_Koro_ni_Rei">Higurashi no Naku Koro ni Rei</a><br>
      #   Side story: <a href="http://myanimelist.net/anime/6064/Higurashi_no_Naku_Koro_ni_Kai_DVD_Specials">Higurashi no Naku Koro ni Kai DVD Specials</a><br>
      related_anime_h2 = right_column_nodeset.at('//h2[text()="Related Anime"]')
      if related_anime_h2

        # Get all text between <h2>Related Anime</h2> and the next <h2> tag.
        match_data = related_anime_h2.parent.to_s.match(%r{<h2>Related Anime</h2>(.+?)<h2>}m)

        if match_data
          related_anime_text = match_data[1]

          if related_anime_text.match %r{Adaptation: ?(<a .+?)<br}
            $1.scan(%r{<a href="(http://myanimelist.net/manga/(\d+)/.*?)">(.+?)</a>}) do |url, manga_id, title|
              anime.manga_adaptations << {
                :manga_id => manga_id,
                :title => title,
                :url => url
              }
            end
          end

          if related_anime_text.match %r{Prequel: ?(<a .+?)<br}
            $1.scan(%r{<a href="(http://myanimelist.net/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
              anime.prequels << {
                :anime_id => anime_id,
                :title => title,
                :url => url
              }
            end
          end

          if related_anime_text.match %r{Sequel: ?(<a .+?)<br}
            $1.scan(%r{<a href="(http://myanimelist.net/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
              anime.sequels << {
                :anime_id => anime_id,
                :title => title,
                :url => url
              }
            end
          end

          if related_anime_text.match %r{Side story: ?(<a .+?)<br}
            $1.scan(%r{<a href="(http://myanimelist.net/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
              anime.side_stories << {
                :anime_id => anime_id,
                :title => title,
                :url => url
              }
            end
          end
        end

      end

      anime
    end

    def self.update(id, cookie_string, options)

      # Convert status to the number values that MyAnimeList uses.
      # 1 = Watching, 2 = Completed, 3 = On-hold, 4 = Dropped, 6 = Plan to Watch
      status = case options[:status]
      when 'Watching', 'watching', 1
        1
      when 'Completed', 'completed', 2
        2
      when 'On-hold', 'on-hold', 3
        3
      when 'Dropped', 'dropped', 4
        4
      when 'Plan to Watch', 'plan to watch', 6
        6
      else
        1
      end

      curl = Curl::Easy.new('http://myanimelist.net/includes/ajax.inc.php?t=62')
      curl.cookies = cookie_string
      params = [
        Curl::PostField.content('aid', id),
        Curl::PostField.content('status', status)
      ]
      params << Curl::PostField.content('epsseen', options[:episodes]) if options[:episodes]
      params << Curl::PostField.content('score', options[:score]) if options[:score]
      curl.http_post(*params)
    end

    def other_titles
      @other_titles ||= {}
    end

    def genres
      @genres ||= []
    end

    def tags
      @tags ||= []
    end

    def manga_adaptations
      @manga_adaptations ||= []
    end

    def prequels
      @prequels ||= []
    end

    def sequels
      @sequels ||= []
    end

    def side_stories
      @side_stories ||= []
    end

    def to_json
      {
        :id => id,
        :title => title,
        :other_titles => other_titles,
        :synopsis => synopsis,
        :type => type,
        :rank => rank,
        :popularity_rank => popularity_rank,
        :episodes => episodes,
        :status => status,
        :genres => genres,
        :tags => tags,
        :classification => classification,
        :members_score => members_score,
        :members_count => members_count,
        :favorited_count => favorited_count,
        :manga_adaptations => manga_adaptations,
        :prequels => prequels,
        :sequels => sequels,
        :side_stories => side_stories,
        :watched_episodes => watched_episodes,
        :score => score,
        :watched_status => watched_status
      }.to_json
    end
  end # END class Anime

end