module MyAnimeList
  class Manga
    attr_accessor :id, :title, :rank, :popularity_rank, :image_url, :volumes, :chapters,
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
        anime.id = details_link['href'][%r{http://myanimelist.net/manga/(\d+)/.*?}, 1].to_i
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
      end

      xml.target!
    end
  end
end