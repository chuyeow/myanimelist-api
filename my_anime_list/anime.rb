module MyAnimeList

  class Anime
    attr_accessor :id, :title, :rank, :popularity_rank, :image_url, :episodes, :status, :classification,
                  :members_score, :members_count, :favorited_count, :synopsis
    attr_reader :type
    attr_writer :genres, :tags, :other_titles, :manga_adaptations, :prequels, :sequels, :side_stories

    # These attributes are specific to a user-anime pair, probably should go into another model.
    attr_accessor :watched_episodes, :score
    attr_reader :watched_status

    # Scrape anime details page on MyAnimeList.net. Very fragile!
    def self.scrape_anime(id, cookie_string = nil)
      curl = Curl::Easy.new("http://myanimelist.net/anime/#{id}")
      curl.headers['User-Agent'] = 'MyAnimeList Unofficial API (http://mal-api.com/)'
      curl.cookies = cookie_string if cookie_string
      begin
        curl.perform
      rescue Exception => e
        raise NetworkError("Network error scraping anime with ID=#{id}. Original exception: #{e.message}.", e)
      end

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

      # <h2>My Info</h2>
      # <a name="addtolistanchor"></a>
      # <div id="addtolist" style="display: block;">
      #   <input type="hidden" id="myinfo_anime_id" value="934">
      #   <input type="hidden" id="myinfo_curstatus" value="2">
      #
      #   <table border="0" cellpadding="0" cellspacing="0" width="100%">
      #     <tr>
      #       <td class="spaceit">Status:</td>
      #       <td class="spaceit"><select id="myinfo_status" name="myinfo_status" onchange="checkEps(this);" class="inputtext"><option value="1" selected>Watching</option><option value="2" >Completed</option><option value="3" >On-Hold</option><option value="4" >Dropped</option><option value="6" >Plan to Watch</option></select></td>
      #     </tr>
      #     <tr>
      #       <td class="spaceit">Eps Seen:</td>
      #       <td class="spaceit"><input type="text" id="myinfo_watchedeps" name="myinfo_watchedeps" size="3" class="inputtext" value="26"> / <span id="curEps">26</span></td>
      #     </tr>
      #     <tr>
      #       <td class="spaceit">Your Score:</td>
      #         <td class="spaceit"><select id="myinfo_score" name="myinfo_score" class="inputtext"><option value="0">Select</option><option value="10" >(10) Masterpiece</option><option value="9" >(9) Great</option><option value="8" >(8) Very Good</option><option value="7" >(7) Good</option><option value="6" >(6) Fine</option><option value="5" >(5) Average</option><option value="4" >(4) Bad</option><option value="3" >(3) Very Bad</option><option value="2" >(2) Horrible</option><option value="1" >(1) Unwatchable</option></select></td>
      #     </tr>
      #     <tr>
      #       <td>&nbsp;</td>
      #       <td><input type="button" name="myinfo_submit" value="Update" onclick="myinfo_updateInfo(1100070);" class="inputButton"> <small><a href="http://www.myanimelist.net/panel.php?go=edit&id=1100070">Edit Details</a></small></td>
      #     </tr>
      #   </table>
      watched_status_select_node = doc.at('select#myinfo_status')
      if watched_status_select_node && (selected_option = watched_status_select_node.at('option[selected="selected"]'))
        anime.watched_status = selected_option['value']
      end
      episodes_input_node = doc.at('input#myinfo_watchedeps')
      if episodes_input_node
        anime.watched_episodes = episodes_input_node['value'].to_i
      end
      score_select_node = doc.at('select#myinfo_score')
      if score_select_node && (selected_option = score_select_node.at('option[selected="selected"]'))
        anime.score = selected_option['value']
      end

      anime
    rescue Exception => e
      raise UnknownError.new("Error scraping anime with ID=#{id}. Original exception: #{e.message}.", e)
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
      curl.headers['User-Agent'] = 'MyAnimeList Unofficial API (http://mal-api.com/)'
      curl.cookies = cookie_string
      params = [
        Curl::PostField.content('aid', id),
        Curl::PostField.content('status', status)
      ]
      params << Curl::PostField.content('epsseen', options[:episodes]) if options[:episodes]
      params << Curl::PostField.content('score', options[:score]) if options[:score]

      begin
        curl.http_post(*params)
      rescue Exception => e
        raise MyAnimeList::UpdateError.new("Error updating anime with ID=#{id}. Original exception: #{e.message}", e)
      end

      # Update is successful for a HTTP 200 response with this string.
      curl.response_code == 200 && curl.body_str == 'Successfully Updated'
    end

    def watched_status=(value)
      @watched_status = case value
      when /watching/i, '1', 1
        :watching
      when /completed/i, '2', 2
        :completed
      when /on-hold/i, /onhold/i, '3', 3
        :on_hold
      when /dropped/i, '4', 3
        :dropped
      when /plan to watch/i, /plantowatch/i, '6', 6
        :plan_to_watch
      else
        :watching
      end
    end

    def type=(value)
      @type = case value
      when /TV/i, '1', 1
        :TV
      when /OVA/i, '2', 2
        :OVA
      when /Movie/i, '3', 3
        :Movie
      when /Special/i, '4', 4
        :Special
      when /ONA/i, '5', 5
        :ONA
      when /Music/i, '6', 6
        :Music
      else
        :TV
      end
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