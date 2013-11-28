module MyAnimeList
  class Manga
    attr_accessor :id, :title, :rank, :image_url, :popularity_rank, :volumes, :chapters,
                  :members_score, :members_count, :favorited_count, :synopsis
    attr_accessor :listed_manga_id
    attr_reader :type, :status
    attr_writer :genres, :tags, :other_titles, :anime_adaptations, :related_manga, :alternative_versions

    # These attributes are specific to a user-manga pair.
    attr_accessor :volumes_read, :chapters_read, :score
    attr_reader :read_status

    # Scrape manga details page on MyAnimeList.net.
    def self.scrape_manga(id, cookie_string = nil)
      curl = Curl::Easy.new("http://myanimelist.net/manga/#{id}")
      curl.headers['User-Agent'] = ENV['USER_AGENT']
      curl.cookies = cookie_string if cookie_string
      begin
        curl.perform
      rescue Exception => e
        raise MyAnimeList::NetworkError.new("Network error scraping manga with ID=#{id}. Original exception: #{e.message}.", e)
      end

      response = curl.body_str

      # Check for missing manga.
      raise MyAnimeList::NotFoundError.new("Manga with ID #{id} doesn't exist.", nil) if response =~ /No manga found/i

      manga = parse_manga_response(response)

      manga
    rescue MyAnimeList::NotFoundError => e
      raise
    rescue Exception => e
      raise MyAnimeList::UnknownError.new("Error scraping manga with ID=#{id}. Original exception: #{e.message}.", e)
    end

    def self.add(id, cookie_string, options)
      # This is the same as self.update except that the "status" param is required and the URL is
      # http://myanimelist.net/includes/ajax.inc.php?t=49.

      # Default read_status to 1/reading if not given.
      options[:status] = 1 if options[:status] !~ /\S/
      options[:new] = true

      update(id, cookie_string, options)
    end

    def self.update(id, cookie_string, options)

      # Convert status to the number values that MyAnimeList uses.
      # 1 = Reading, 2 = Completed, 3 = On-hold, 4 = Dropped, 6 = Plan to Read
      status = case options[:status]
      when 'Reading', 'reading', 1
        1
      when 'Completed', 'completed', 2
        2
      when 'On-hold', 'on-hold', 3
        3
      when 'Dropped', 'dropped', 4
        4
      when 'Plan to Read', 'plan to read', 6
        6
      else
        1
      end

      # There're different URLs to POST to for adding and updating a manga.
      url = options[:new] ? 'http://myanimelist.net/includes/ajax.inc.php?t=49' : 'http://myanimelist.net/includes/ajax.inc.php?t=34'

      curl = Curl::Easy.new(url)
      curl.headers['User-Agent'] = ENV['USER_AGENT']
      curl.cookies = cookie_string
      params = [
        Curl::PostField.content('mid', id),
        Curl::PostField.content('status', status)
      ]
      params << Curl::PostField.content('chapters', options[:chapters]) if options[:chapters]
      params << Curl::PostField.content('volumes', options[:volumes]) if options[:volumes]
      params << Curl::PostField.content('score', options[:score]) if options[:score]

      begin
        curl.http_post(*params)
      rescue Exception => e
        raise MyAnimeList::UpdateError.new("Error updating manga with ID=#{id}. Original exception: #{e.message}", e)
      end

      if options[:new]
        # An add is successful for an HTTP 200 response containing "successful".
        # The MyAnimeList site is actually pretty bad and seems to respond with 200 OK for all requests.
        # It's also oblivious to IDs for non-existent manga and responds wrongly with a "successful" message.
        # It responds with an empty response body for bad adds or if you try to add a manga that's already on the
        # manga list.
        # Due to these limitations, we will return false if the response body doesn't match "successful" and assume that
        # anything else is a failure.
        return curl.response_code == 200 && curl.body_str =~ /Added/i
      else
        # Update is successful for an HTTP 200 response with this string.
        curl.response_code == 200 && curl.body_str =~ /Updated/i
      end
    end

    def self.delete(id, cookie_string)
      manga = scrape_manga(id, cookie_string)

      curl = Curl::Easy.new("http://myanimelist.net/panel.php?go=editmanga&id=#{manga.listed_manga_id}")
      curl.headers['User-Agent'] = ENV['USER_AGENT']
      curl.cookies = cookie_string

      begin
        curl.http_post(
          Curl::PostField.content('entry_id', manga.listed_manga_id),
          Curl::PostField.content('manga_id', id),
          Curl::PostField.content('submitIt', '3')
        )
      rescue Exception => e
        raise MyAnimeList::UpdateError.new("Error deleting manga with ID=#{id}. Original exception: #{e.message}", e)
      end

      # Deletion is successful for an HTTP 200 response with this string.
      if curl.response_code == 200 && curl.body_str =~ /Successfully deleted manga entry/i
        manga # Return the original manga if successful.
      else
        false
      end
    end

    def self.search(query)

      begin
        response = Net::HTTP.start('myanimelist.net', 80) do |http|
          http.get("/manga.php?c[]=a&c[]=b&c[]=c&c[]=d&c[]=e&c[]=f&c[]=g&q=#{Curl::Easy.new.escape(query)}", {'User-Agent' => ENV['USER_AGENT']})
        end

        case response
        when Net::HTTPRedirection
          redirected = true

          # Strip everything after the manga ID - in cases where there is a non-ASCII character in the URL,
          # MyAnimeList.net will return a page that says "Access has been restricted for this account".
          redirect_url = response['location'].sub(%r{(http://myanimelist.net/manga/\d+)/?.*}, '\1')

          response = Net::HTTP.start('myanimelist.net', 80) do |http|
            http.get(redirect_url, {'User-Agent' => ENV['USER_AGENT']})
          end
        end

      rescue Exception => e
        raise MyAnimeList::UpdateError.new("Error searching manga with query '#{query}'. Original exception: #{e.message}", e)
      end

      results = []
      if redirected
        # If there's a single redirect, it means there's only 1 match and MAL is redirecting to the manga's details
        # page.

        manga = parse_manga_response(response.body)
        results << manga

      else
        # Otherwise, parse the table of search results.

        doc = Nokogiri::HTML(response.body)
        results_table = doc.xpath('//div[@id="content"]/div[2]/table')

        results_table.xpath('//tr').each do |results_row|

          manga_title_node = results_row.at('td a strong')
          next unless manga_title_node
          url = manga_title_node.parent['href']
          next unless url.match %r{http://myanimelist.net/manga/(\d+)/?.*}

          manga = Manga.new
          manga.id = $1.to_i
          manga.title = manga_title_node.text
          if image_node = results_row.at('td a img')
            manga.image_url = image_node['src']
          end

          table_cell_nodes = results_row.search('td')

          manga.volumes = table_cell_nodes[3].text.to_i
          manga.chapters = table_cell_nodes[4].text.to_i
          manga.members_score = table_cell_nodes[5].text.to_f
          synopsis_node = results_row.at('div.spaceit_pad')
          if synopsis_node
            synopsis_node.search('a').remove
            manga.synopsis = synopsis_node.text.strip
          end
          manga.type = table_cell_nodes[2].text

          results << manga
        end
      end

      results
    end

    def read_status=(value)
      @read_status = case value
      when /reading/i, '1', 1
        :reading
      when /completed/i, '2', 2
        :completed
      when /on-hold/i, /onhold/i, '3', 3
        :"on-hold"
      when /dropped/i, '4', 4
        :dropped
      when /plan/i, '6', 6
        :"plan to read"
      else
        :reading
      end
    end

    def status=(value)
      @status = case value
      when '2', 2, /finished/i
        :finished
      when '1', 1, /publishing/i
        :publishing
      when '3', 3, /not yet published/i
        :"not yet published"
      else
        :finished
      end
    end

    def type=(value)
      @type = case value
      when /manga/i, '1', 1
        :Manga
      when /novel/i, '2', 2
        :Novel
      when /one shot/i, '3', 3
        :"One Shot"
      when /doujin/i, '4', 4
        :Doujin
      when /manwha/i, '5', 5
        :Manwha
      when /manhua/i, '6', 6
        :Manhua
      when /OEL/i, '7', 7 # "OEL manga = Original English-language manga"
        :OEL
      else
        :Manga
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

    def anime_adaptations
      @anime_adaptations ||= []
    end

    def related_manga
      @related_manga ||= []
    end

    def alternative_versions
      @alternative_versions ||= []
    end

    def attributes
      {
        :id => id,
        :title => title,
        :other_titles => other_titles,
        :rank => rank,
        :image_url => image_url,
        :type => type,
        :status => status,
        :volumes => volumes,
        :chapters => chapters,
        :genres => genres,
        :members_score => members_score,
        :members_count => members_count,
        :popularity_rank => popularity_rank,
        :favorited_count => favorited_count,
        :tags => tags,
        :synopsis => synopsis,
        :anime_adaptations => anime_adaptations,
        :related_manga => related_manga,
        :alternative_versions => alternative_versions,
        :read_status => read_status,
        :listed_manga_id => listed_manga_id,
        :chapters_read => chapters_read,
        :volumes_read => volumes_read,
        :score => score
      }
    end

    def to_json(*args)
      attributes.to_json(*args)
    end

    def to_xml(options = {})
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct! unless options[:skip_instruct]
      xml.anime do |xml|
        xml.id id
        xml.title title
        xml.rank rank
        xml.image_url image_url
        xml.type type.to_s
        xml.status status.to_s
        xml.volumes volumes
        xml.chapters chapters
        xml.members_score members_score
        xml.members_count members_count
        xml.popularity_rank popularity_rank
        xml.favorited_count favorited_count
        xml.synopsis synopsis
        xml.read_status read_status.to_s
        xml.chapters_read chapters_read
        xml.volumes_read volumes_read
        xml.score score

        other_titles[:synonyms].each do |title|
          xml.synonym title
        end if other_titles[:synonyms]
        other_titles[:english].each do |title|
          xml.english_title title
        end if other_titles[:english]
        other_titles[:japanese].each do |title|
          xml.japanese_title title
        end if other_titles[:japanese]

        genres.each do |genre|
          xml.genre genre
        end
        tags.each do |tag|
          xml.tag tag
        end

        anime_adaptations.each do |anime|
          xml.anime_adaptation do |xml|
            xml.anime_id  anime[:anime_id]
            xml.title     anime[:title]
            xml.url       anime[:url]
          end
        end

        related_manga.each do |manga|
          xml.related_manga do |xml|
            xml.manga_id  manga[:manga_id]
            xml.title     manga[:title]
            xml.url       manga[:url]
          end
        end

        alternative_versions.each do |manga|
          xml.alternative_version do |xml|
            xml.manga_id  manga[:manga_id]
            xml.title     manga[:title]
            xml.url       manga[:url]
          end
        end
      end

      xml.target!
    end

    private

    def self.parse_manga_response(response)

      doc = Nokogiri::HTML(response)

      manga = Manga.new

      # Manga ID.
      # Example:
      # <input type="hidden" value="104" name="mid" />
      manga_id_input = doc.at('input[@name="mid"]')
      if manga_id_input

        manga.id = manga_id_input['value'].to_i
      else
        details_link = doc.at('//a[text()="Details"]')
        manga.id = details_link['href'][%r{http://myanimelist.net/manga/(\d+)/.*?}, 1].to_i
      end

      # Title and rank.
      # Example:
      # <h1>
      #   <div style="float: right; font-size: 13px;">Ranked #8</div>Yotsuba&!
      #   <span style="font-weight: normal;"><small>(Manga)</small></span>
      # </h1>
      manga.title = doc.at(:h1).children.find { |o| o.text? }.to_s.strip
      manga.rank = doc.at('h1 > div').text.gsub(/\D/, '').to_i

      # Image URL.
      if image_node = doc.at('div#content tr td div img')
        manga.image_url = image_node['src']
      end

      # -
      # Extract from sections on the left column: Alternative Titles, Information, Statistics, Popular Tags.
      # -
      left_column_nodeset = doc.xpath('//div[@id="content"]/table/tr/td[@class="borderClass"]')

      # Alternative Titles section.
      # Example:
      # <h2>Alternative Titles</h2>
      # <div class="spaceit_pad"><span class="dark_text">English:</span> Yotsuba&!</div>
      # <div class="spaceit_pad"><span class="dark_text">Synonyms:</span> Yotsubato!, Yotsuba and !, Yotsuba!, Yotsubato, Yotsuba and!</div>
      # <div class="spaceit_pad"><span class="dark_text">Japanese:</span> よつばと！</div>
      if (node = left_column_nodeset.at('//span[text()="English:"]')) && node.next
        manga.other_titles[:english] = node.next.text.strip.split(/,\s?/)
      end
      if (node = left_column_nodeset.at('//span[text()="Synonyms:"]')) && node.next
        manga.other_titles[:synonyms] = node.next.text.strip.split(/,\s?/)
      end
      if (node = left_column_nodeset.at('//span[text()="Japanese:"]')) && node.next
        manga.other_titles[:japanese] = node.next.text.strip.split(/,\s?/)
      end


      # Information section.
      # Example:
      # <h2>Information</h2>
      # <div><span class="dark_text">Type:</span> Manga</div>
      # <div class="spaceit"><span class="dark_text">Volumes:</span> Unknown</div>
      # <div><span class="dark_text">Chapters:</span> Unknown</div>
      # <div class="spaceit"><span class="dark_text">Status:</span> Publishing</div>
      # <div><span class="dark_text">Published:</span> Mar  21, 2003 to ?</div>
      # <div class="spaceit"><span class="dark_text">Genres:</span>
      #   <a href="http://myanimelist.net/manga.php?genre[]=4">Comedy</a>,
      #   <a href="http://myanimelist.net/manga.php?genre[]=36">Slice of Life</a>
      # </div>
      # <div><span class="dark_text">Authors:</span>
      #   <a href="http://myanimelist.net/people/1939/Kiyohiko_Azuma">Azuma, Kiyohiko</a> (Story & Art)
      # </div>
      # <div class="spaceit"><span class="dark_text">Serialization:</span>
      #   <a href="http://myanimelist.net/manga.php?mid=23">Dengeki Daioh (Monthly)</a>
      # </div>
      if (node = left_column_nodeset.at('//span[text()="Type:"]')) && node.next
        manga.type = node.next.text.strip
      end
      if (node = left_column_nodeset.at('//span[text()="Volumes:"]')) && node.next
        manga.volumes = node.next.text.strip.gsub(',', '').to_i
        manga.volumes = nil if manga.volumes == 0
      end
      if (node = left_column_nodeset.at('//span[text()="Chapters:"]')) && node.next
        manga.chapters = node.next.text.strip.gsub(',', '').to_i
        manga.chapters = nil if manga.chapters == 0
      end
      if (node = left_column_nodeset.at('//span[text()="Status:"]')) && node.next
        manga.status = node.next.text.strip
      end
      if node = left_column_nodeset.at('//span[text()="Genres:"]')
        node.parent.search('a').each do |a|
          manga.genres << a.text.strip
        end
      end

      # Statistics
      # Example:
      # <h2>Statistics</h2>
      # <div><span class="dark_text">Score:</span> 8.90<sup><small>1</small></sup> <small>(scored by 4899 users)</small>
      # </div>
      # <div class="spaceit"><span class="dark_text">Ranked:</span> #8<sup><small>2</small></sup></div>
      # <div><span class="dark_text">Popularity:</span> #32</div>
      # <div class="spaceit"><span class="dark_text">Members:</span> 8,344</div>
      # <div><span class="dark_text">Favorites:</span> 1,700</div>
      if (node = left_column_nodeset.at('//span[text()="Score:"]')) && node.next
        manga.members_score = node.next.text.strip.to_f
      end
      if (node = left_column_nodeset.at('//span[text()="Popularity:"]')) && node.next
        manga.popularity_rank = node.next.text.strip.sub('#', '').gsub(',', '').to_i
      end
      if (node = left_column_nodeset.at('//span[text()="Members:"]')) && node.next
        manga.members_count = node.next.text.strip.gsub(',', '').to_i
      end
      if (node = left_column_nodeset.at('//span[text()="Favorites:"]')) && node.next
        manga.favorited_count = node.next.text.strip.gsub(',', '').to_i
      end

      # Popular Tags
      # Example:
      # <h2>Popular Tags</h2>
      # <span style="font-size: 11px;">
      #   <a href="http://myanimelist.net/manga.php?tag=comedy" style="font-size: 24px" title="241 people tagged with comedy">comedy</a>
      #   <a href="http://myanimelist.net/manga.php?tag=slice of life" style="font-size: 11px" title="207 people tagged with slice of life">slice of life</a>
      # </span>
      if (node = left_column_nodeset.at('//span[preceding-sibling::h2[text()="Popular Tags"]]'))
        node.search('a').each do |a|
          manga.tags << a.text
        end
      end


      # -
      # Extract from sections on the right column: Synopsis, Related Manga
      # -
      right_column_nodeset = doc.xpath('//div[@id="content"]/table/tr/td/div/table')

      # Synopsis
      # Example:
      # <h2>Synopsis</h2>
      # Yotsuba's daily life is full of adventure. She is energetic, curious, and a bit odd &ndash; odd enough to be called strange by her father as well as ignorant of many things that even a five-year-old should know. Because of this, the most ordinary experience can become an adventure for her. As the days progress, she makes new friends and shows those around her that every day can be enjoyable.<br />
      # <br />
      # [Written by MAL Rewrite]
      synopsis_h2 = right_column_nodeset.at('//h2[text()="Synopsis"]')
      if synopsis_h2
        node = synopsis_h2.next
        while node
          if manga.synopsis
            manga.synopsis << node.to_s
          else
            manga.synopsis = node.to_s
          end

          node = node.next
        end
      end

      # Related Manga
      # Example:
      # <h2>Related Manga</h2>
      #   Adaptation: <a href="http://myanimelist.net/anime/66/Azumanga_Daioh">Azumanga Daioh</a><br>
      #   Side story: <a href="http://myanimelist.net/manga/13992/Azumanga_Daioh:_Supplementary_Lessons">Azumanga Daioh: Supplementary Lessons</a><br>
      related_manga_h2 = right_column_nodeset.at('//h2[text()="Related Manga"]')
      if related_manga_h2

        # Get all text between <h2>Related Manga</h2> and the next <h2> tag.
        match_data = related_manga_h2.parent.to_s.match(%r{<h2>Related Manga</h2>(.+?)<h2>}m)

        if match_data
          related_anime_text = match_data[1]

          if related_anime_text.match %r{Adaptation: ?(<a .+?)<br}
            $1.scan(%r{<a href="(http://myanimelist.net/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
              manga.anime_adaptations << {
                :anime_id => anime_id,
                :title => title,
                :url => url
              }
            end
          end

          if related_anime_text.match %r{.+: ?(<a .+?)<br}
            $1.scan(%r{<a href="(http://myanimelist.net/manga/(\d+)/.*?)">(.+?)</a>}) do |url, manga_id, title|
              manga.related_manga << {
                :manga_id => manga_id,
                :title => title,
                :url => url
              }
            end
          end

          if related_anime_text.match %r{Alternative versions?: ?(<a .+?)<br}
            $1.scan(%r{<a href="(http://myanimelist.net/manga/(\d+)/.*?)">(.+?)</a>}) do |url, manga_id, title|
              manga.alternative_versions << {
                :manga_id => manga_id,
                :title => title,
                :url => url
              }
            end
          end
        end
      end


      # User's manga details (only available if he authenticates).
      # <h2>My Info</h2>
      # <div id="addtolist" style="display: block;">
      #   <input type="hidden" id="myinfo_manga_id" value="104">
      #   <table border="0" cellpadding="0" cellspacing="0" width="100%">
      #   <tr>
      #     <td class="spaceit">Status:</td>
      #     <td class="spaceit"><select id="myinfo_status" name="myinfo_status" onchange="checkComp(this);" class="inputtext"><option value="1" selected>Reading</option><option value="2" >Completed</option><option value="3" >On-Hold</option><option value="4" >Dropped</option><option value="6" >Plan to Read</option></select></td>
      #   </tr>
      #   <tr>
      #     <td class="spaceit">Chap. Read:</td>
      #     <td class="spaceit"><input type="text" id="myinfo_chapters" size="3" maxlength="4" class="inputtext" value="62"> / <span id="totalChaps">0</span></td>
      #   </tr>
      #   <tr>
      #     <td class="spaceit">Vol. Read:</td>
      #     <td class="spaceit"><input type="text" id="myinfo_volumes" size="3" maxlength="4" class="inputtext" value="5"> / <span id="totalVols">?</span></td>
      #   </tr>
      #   <tr>
      #     <td class="spaceit">Your Score:</td>
      #     <td class="spaceit"><select id="myinfo_score" name="myinfo_score" class="inputtext"><option value="0">Select</option><option value="10" selected>(10) Masterpiece</option><option value="9" >(9) Great</option><option value="8" >(8) Very Good</option><option value="7" >(7) Good</option><option value="6" >(6) Fine</option><option value="5" >(5) Average</option><option value="4" >(4) Bad</option><option value="3" >(3) Very Bad</option><option value="2" >(2) Horrible</option><option value="1" >(1) Unwatchable</option></select></td>
      #   </tr>
      #   <tr>
      #     <td>&nbsp;</td>
      #     <td><input type="button" name="myinfo_submit" value="Update" onclick="myinfo_updateInfo();" class="inputButton"> <small><a href="http://www.myanimelist.net/panel.php?go=editmanga&id=75054">Edit Details</a></small></td>
      #   </tr>
      #   </table>
      # </div>
      read_status_select_node = doc.at('select#myinfo_status')
      if read_status_select_node && (selected_option = read_status_select_node.at('option[selected="selected"]'))
        manga.read_status = selected_option['value']
      end
      chapters_node = doc.at('input#myinfo_chapters')
      if chapters_node
        manga.chapters_read = chapters_node['value'].to_i
      end
      volumes_node = doc.at('input#myinfo_volumes')
      if volumes_node
        manga.volumes_read = volumes_node['value'].to_i
      end
      score_select_node = doc.at('select#myinfo_score')
      if score_select_node && (selected_option = score_select_node.at('option[selected="selected"]'))
        manga.score = selected_option['value'].to_i
      end
      listed_manga_id_node = doc.at('//a[text()="Edit Details"]')
      if listed_manga_id_node
        manga.listed_manga_id = listed_manga_id_node['href'].match('id=(\d+)')[1].to_i
      end

      manga
    end
  end
end
