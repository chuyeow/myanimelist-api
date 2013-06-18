module MyAnimeList
  class Character
    attr_accessor :id, :name, :image_url, :thumb_url, :anime, :manga, :bio, :seiyuu, :eng_name, :jp_name

    def self.scrape_character(id, cookie_string = nil)
      curl = Curl::Easy.new("http://myanimelist.net/character/#{id}")
      curl.headers["User-Agent"] = "MyAnimeList Unofficial API (http://mal-api.com/)"
      curl.cookies = cookie_strnig if cookie_string
      begin
        curl.perform
      rescue Exception => e
        raise MyAnimeList::NetworkError.new("Network error scraping character with ID=#{id}. Original exception: #{e.message}.", e)
      end

      response = curl.body_str

      raise MyAnimeList::NotFoundError.new("Character with ID #{id} doesn't exist.", nil) if response =~ /Invalid ID provided/i

      character = parse_character_response(response)
      character

    rescue MyAnimeList::NotFoundError => e
      raise
    rescue Exception => e
      raise MyAnimeList::UnknownError.new("Error scraping character with ID=#{id}. Original exception: #{e.message}.", e)
    end

    def anime
      @anime ||= []
    end

    def manga
      @manga ||= []
    end

    def seiyuu
      @seiyuu ||= []
    end

    def bio
      @bio ||= ""
    end

    def attributes
      {
        :id => id,
        :name => name,
        :eng_name => eng_name,
        :jp_name => jp_name,
        :image_url => image_url,
        :thumb_url => thumb_url,
        :anime => anime,
        :manga => manga,
        :bio => bio,
        :seiyuu => seiyuu
      }
    end

    def to_json(*args)
      attributes.to_json(*args)
    end

    def to_xml(options = {})
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct! unless options[:skip_instruct]
      xml.character do |xml|
        xml.id id
        xml.name name
        xml.eng_name eng_name
        xml.jp_name jp_name
        xml.image_url image_url
        xml.thumb_url thumb_url
        xml.bio bio

        anime.each do |o|
          xml.anime do |xml|
            xml.id o[:id]
            xml.title o[:title]
            xml.role o[:role]
            xml.image_url o[:image_url]
            xml.thumb_url o[:thumb_url]
          end
        end
        manga.each do |o|
          xml.manga do |xml|
            xml.id o[:id]
            xml.title o[:title]
            xml.role o[:role]
            xml.image_url o[:image_url]
            xml.thumb_url o[:thumb_url]
          end
        end
        seiyuu.each do |o|
          xml.seiyuu do |xml|
            xml.id o[:id]
            xml.name o[:name]
            xml.nation o[:nation]
            xml.image_url o[:image_url]
            xml.thumb_url o[:thumb_url]
          end
        end

      end
    end

    private
    
      def self.parse_character_response(response)
        character = Character.new

        doc = Nokogiri::HTML(response)

        details_link = doc.at('//a[text()="Details"]')
        character.id = details_link['href'][%r{http://myanimelist.net/character/(\d+)/.*?}, 1].to_i
        character.name = doc.at(:h1).children.find { |o| o.text? }.to_s

        if image_node = doc.at("div#content tr td div img")
          character.image_url = image_node["src"]
        end

        left_column_nodeset = doc.xpath('//div[@id="content"]/table/tr/td[@class="borderClass"]')

        anime_list = []
        manga_list = []

        if (node = left_column_nodeset.at('div[text()="Animeography"]'))
            anime_list_nodeset = node.next.next.css("tr")

            anime_list_nodeset.each do |node|
              anime = Hash.new
              info_nodes = node.css("td")
              image_node = info_nodes[0]
              title_node = info_nodes[1]
              anime[:id] = id_from_url(image_node.at("a")["href"])
              anime[:thumb_url] = image_node.at("a img")["src"]
              anime[:image_url] = image_from_thumb_url(anime[:thumb_url], "v")
              anime[:title] = title_node.at("a").text
              anime[:role] = title_node.at("small").text
              anime_list.push anime
            end
        end

        if (node = left_column_nodeset.at('div[text()="Mangaography"]'))
            manga_list_nodeset = node.next.next.css("tr")
            manga_list_nodeset.each do |node|
              manga = Hash.new
              info_nodes = node.css("td")
              image_node = info_nodes[0]
              title_node = info_nodes[1]
              manga[:id] = id_from_url(image_node.at("a")["href"])
              manga[:thumb_url] = image_node.at("a img")["src"]
              manga[:image_url] = image_from_thumb_url(manga[:thumb_url], "v")
              manga[:title] = title_node.at("a").text
              manga[:role] = title_node.at("small").text
              manga_list.push manga
            end
        end

        character.anime = anime_list
        character.manga = manga_list

        content_divs = doc.xpath('//div[@class="normal_header"]')
        name_div = content_divs[2]
        va_div = content_divs[3]

        character.eng_name = name_div.children[0].text
        character.jp_name = name_div.children[1].text

        bio_div = name_div.next

        bio = []

        while bio_div != va_div
          bio.push bio_div.to_s
          bio_div = bio_div.next
        end
        character.bio = bio.join("")

        seiyuu_list = []
        va_div = va_div.next.next

        while va_div.name != "br"
          seiyuu = Hash.new
          info_nodes = va_div.css("td")
          thumb_node = info_nodes[0]
          seiyuu_node = info_nodes[1]
          seiyuu[:id] = id_from_url(thumb_node.at("a")["href"])
          seiyuu[:thumb_url] = thumb_node.at("a img")["src"]
          seiyuu[:image_url] = image_from_thumb_url(seiyuu[:thumb_url], "v")
          seiyuu[:name] = seiyuu_node.at("a").text
          seiyuu[:nation] = seiyuu_node.at("small").text
          seiyuu_list.push seiyuu
          va_div = va_div.next
        end

        character.seiyuu = seiyuu_list
        character
      end

      def self.id_from_url(url)
#        split = url.split("/")
#        split[split.length-2].to_i
        url[%r{http://myanimelist.net/(\w+)/(\d+)/.*?}, 2].to_i
      end

      def self.image_from_thumb_url(url, char)
        thumb_url = String::new(url)
        t_pos = thumb_url.rindex(".")
        if thumb_url[t_pos - 1] == char
          thumb_url[t_pos - 1] = ""
        end
        thumb_url
      end
  end
end
