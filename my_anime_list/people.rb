module MyAnimeList
  class People
    attr_accessor :id, :name, :thumb_url, :image_url, :given_name, :family_name,
      :birthday, :website, :more, :seiyuu_roles, :anime_staff_roles, :published_manga

    def self.scrape_person(id, cookie_string = nil)
      curl = Curl::Easy.new("http://myanimelist.net/people/#{id}")
      curl.headers["User-Agent"] = "MyAnimeList Unofficial API (http://mal-api.com/)"
      curl.cookies = cookie_strnig if cookie_string
      begin
        curl.perform
      rescue Exception => e
        raise MyAnimeList::NetworkError.new("Network error scraping Person with ID=#{id}. Original exception: #{e.message}.", e)
      end
      response = curl.body_str

      raise MyAnimeList::NotFoundError.new("Person with ID #{id} doesn't exist.", nil) if response =~ /Invalid ID provided/i

      person = parse_people_response(response)
      person

    rescue MyAnimeList::NotFoundError => e
      raise
    rescue Exception => e
      raise MyAnimeList::UnknownError.new("Error scraping person with ID=#{id}. Original exception: #{e.message}.", e)
    end

    def anime_staff_roles
      @anime_staff_roles ||= []
    end

    def published_manga
      @published_manga ||= []
    end

    def seiyuu_roles
      @seiyuu_roles ||= []
    end

    def bio
      @bio ||= ""
    end

    def attributes
      {
        :id => id,
        :name => name,
        :image_url => image_url,
        :thumb_url => thumb_url,
        :given_name => given_name,
        :family_name => family_name,
        :birthday => birthday,
        :website => website,
        :more => more,
        :seiyuu_roles => seiyuu_roles,
        :anime_staff_roles => anime_staff_roles,
        :published_manga => published_manga
      }
    end

    def to_xml(options = {})
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct! unless options[:skip_instruct]
      xml.person do |xml|
        xml.id id
        xml.name name
        xml.given_name given_name
        xml.family_name family_name
        xml.image_url image_url
        xml.thumb_url thumb_url
        xml.birthday birthday
        xml.website website
        xml.more more
        seiyuu_roles.each do |o|
          xml.seiyuu_roles do |xml|
            xml.id o[:id]
            xml.title o[:title]
            xml.image_url o[:image_url]
            xml.thumb_url o[:thumb_url]
            xml.character do |xml|
              xml.id o[:character][:id]
              xml.name o[:character][:name]
              xml.role o[:character][:role]
              xml.image_url o[:character][:image_url]
              xml.thumb_url o[:character][:thumb_url]
            end
          end
        end
        anime_staff_roles.each do |o|
          xml.anime_staff_roles do |xml|
            xml.id o[:id]
            xml.title o[:title]
            xml.role o[:role]
            xml.image_url o[:image_url]
            xml.thumb_url o[:thumb_url]
          end
        end
        published_manga.each do |o|
          xml.published_manga do |xml|
            xml.id o[:id]
            xml.title o[:title]
            xml.role o[:role]
            xml.image_url o[:image_url]
            xml.thumb_url o[:thumb_url]
          end
        end

      end
    end

    def to_json(*args)
      attributes.to_json(*args)
    end

    private
    
      def self.parse_people_response(response)
        person = People.new

        doc = Nokogiri::HTML(response)

        details_link = doc.at('//a[text()="Details"]')
        person.id = details_link['href'][%r{http://myanimelist.net/people/(\d+)/.*?}, 1].to_i
        
        all_content = doc.at('//div[@id="contentWrapper"]')
        person.name = all_content.at('h1').text
 
        content = all_content.at('div[@id="content"]')

        image_node = content.at('img')
        person.image_url = image_node['src']

        given_name_node = content.at('span[text()="Given name:"]')
        if given_name_node != nil
          person.given_name = given_name_node.next.text
        end

        
        family_name_node = content.at('span[text()="Family name:"]')
        if family_name_node != nil
          person.family_name = family_name_node.next.text
        end


        birthday_node = content.at('span[text()="Birthday:"]')
        if birthday_node != nil
          person.birthday = birthday_node.next.text
        end

        website_node = content.at('span[text()="Website:"]')
        if website_node != nil
          person.website = website_node.next.next["href"]
        end

        more_node = content.at('span[text()="More:"]').parent.next

        more = []
        while more_node != nil 
          if more_node.name == "text"
            more.push more_node
          end
          more_node = more_node.next
        end

        person.more = more.join ""

        seiyuu_roles = []
        va_list = content.at('div[text()="Voice Acting Roles"]')
        if not va_list.next.text.match('No voice acting roles have been added yet')
          table = va_list.next
          table.css("tr").each do |cells|
            anime = Hash.new
            character = Hash.new
            nodes = cells.css("td")
            image_node = nodes[0]
            info_node = nodes[1]
            char_info_node = nodes[2]
            char_image_node = nodes[3]

            anime[:id] = id_from_url(info_node.at('a')['href'])
            anime[:title] = info_node.at('a').text
            anime[:thumb_url] = image_node.at('img')['src']
            anime[:image_url] = image_from_thumb_url(anime[:thumb_url], "v")
            character[:id] = id_from_url(char_info_node.at('a')['href'])
            character[:name] = char_info_node.at('a').text
            character[:role] = char_info_node.at('div').text
            character[:thumb_url] = char_image_node.at('img')['src']
            character[:image_url] = image_from_thumb_url(character[:thumb_url], "t")
            anime[:character] = character
            seiyuu_roles.push anime
          end
        end

        person.seiyuu_roles = seiyuu_roles

        anime_staff_roles = []
        anime_staff_list = content.at('div[text()="Anime Staff Positions"]')
        if not anime_staff_list.next.text.match('This person has not worked on any anime.')
          table = anime_staff_list.next
          table.css("tr").each do |cells|
            anime = Hash.new
            nodes = cells.css("td") 
            image_node = nodes[0]
            info_node = nodes[1]
            anime[:id] = id_from_url( info_node.at('a')['href']) #id
            anime[:title] = info_node.at('a').text #name
            anime[:role] = info_node.at("small").text + info_node.at("small").next.text #role description - may be null
            anime[:thumb_url] = image_node.at('img')['src'] #thumb
            anime[:image_url] = image_from_thumb_url(anime[:thumb_url], "v")
            anime_staff_roles.push anime
          end
        end

        person.anime_staff_roles = anime_staff_roles

        published_manga = []
        published_manga_list = content.at('div[text()="Published Manga"]')
        if not published_manga_list.next.text.match('This person has not published any manga.')
          table = published_manga_list.next
          table.css("tr").each do |cells|
            manga = Hash.new
            nodes = cells.css("td") 
            image_node = nodes[0]
            info_node = nodes[1]
            manga[:id] = id_from_url(info_node.at('a')['href'])
            manga[:title] = info_node.at('a').text #name
            manga[:role] = info_node.at("small").text #role
            manga[:thumb_url] = image_node.at('img')['src'] #thumb
            manga[:image_url] = image_from_thumb_url(manga[:thumb_url], "v")
            published_manga.push manga
          end
        end
        person.published_manga = published_manga
        person
      end

      def self.id_from_url(url)
        url[%r{http://myanimelist.net/(\w+)/(\d+)/.*?}, 2].to_i
       # split = url.split("/")
       # split[split.length-2].to_i
      end

      def self.image_from_thumb_url(url, char)
        thumb_url = String::new(url)
        t_pos = thumb_url.rindex(".")
        if thumb_url[t_pos - 1] == char
          thumb_url[t_pos - 1] = ""
        end
        thumb_url
      end

      def to_s
        "#{@name} #{@id} #{@given_name} #{@family_name} #{@website} #{@birthday} #{@more} #{@seiyuu_roles} #{@anime_staff_roles} #{@published_manga}"
      end
  end
end
