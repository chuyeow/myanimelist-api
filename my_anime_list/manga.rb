module MyAnimeList
  class Manga
    attr_accessor :id, :title, :rank, :image_url, :popularity_rank, :volumes, :chapters,
                  :members_score, :members_count, :favorited_count, :synopsis
    attr_reader :type, :status
    attr_writer :genres, :tags, :other_titles, :anime_adaptations, :related_manga

    # These attributes are specific to a user-manga pair.
    attr_accessor :volumes_read, :chapters_read, :score
    attr_reader :read_status

    # Scrape manga details page on MyAnimeList.net.
    def self.scrape_manga(id, cookie_string = nil)
      curl = Curl::Easy.new("http://myanimelist.net/manga/#{id}")
      curl.headers['User-Agent'] = 'MyAnimeList Unofficial API (http://mal-api.com/)'
      curl.cookies = cookie_string if cookie_string
      begin
        curl.perform
      rescue Exception => e
        raise MyAnimeList::NetworkError.new("Network error scraping manga with ID=#{id}. Original exception: #{e.message}.", e)
      end

      response = curl.body_str

      # Check for missing manga.
      raise MyAnimeList::NotFoundError.new("Manga with ID #{id} doesn't exist.", nil) if response =~ /No manga found/i

      manga = Manga.new

      doc = Nokogiri::HTML(response)

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
      if image_node = doc.at('div#rightcontent a img')
        manga.image_url = image_node['src']
      end

      # -
      # Extract from sections on the left column: Alternative Titles, Information, Statistics, Popular Tags.
      # -
      left_column_nodeset = doc.xpath('//div[@id="rightcontent"]/table/tr/td[@class="borderClass"]')

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
      right_column_nodeset = doc.xpath('//div[@id="rightcontent"]/table/tr/td/div/table')

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

      manga
    rescue MyAnimeList::NotFoundError => e
      raise
    rescue Exception => e
      raise MyAnimeList::UnknownError.new("Error scraping manga with ID=#{id}. Original exception: #{e.message}.", e)
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
        :synopsis => synopsis
      }
    end

    def to_json
      attributes.to_json
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
      end

      xml.target!
    end
  end
end