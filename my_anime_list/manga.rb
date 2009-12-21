module MyAnimeList
  class Manga
    attr_accessor :id, :title, :rank, :image_url, :popularity_rank, :volumes, :chapters,
                  :members_score, :members_count, :favorited_count, :synopsis
    attr_reader :status
    attr_writer :genres, :other_titles, :anime_adaptations, :related_manga

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

      manga
    rescue MyAnimeList::NotFoundError => e
      raise
    rescue Exception => e
      raise MyAnimeList::UnknownError.new("Error scraping manga with ID=#{id}. Original exception: #{e.message}.", e)
    end

    def status=(value)
      @status = case value
      when /finished/i
        :finished
      when /publishing/i
        :publishing
      when /not yet published/i
        :"Not yet published"
      else
        :finished
      end
    end

    def other_titles
      @other_titles ||= {}
    end

    def attributes
      {
        :id => id,
        :title => title,
        :other_titles => other_titles,
        :rank => rank,
        :image_url => image_url
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

        other_titles[:synonyms].each do |title|
          xml.synonym title
        end if other_titles[:synonyms]
        other_titles[:english].each do |title|
          xml.english_title title
        end if other_titles[:english]
        other_titles[:japanese].each do |title|
          xml.japanese_title title
        end if other_titles[:japanese]
      end

      xml.target!
    end
  end
end