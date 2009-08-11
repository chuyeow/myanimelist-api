require 'curb'
require 'nokogiri'
require 'json'
require 'my_anime_list'


# Sinatra settings.
set :sessions, true
JSON_RESPONSE_MIME_TYPE = 'text/javascript'
mime :json, JSON_RESPONSE_MIME_TYPE

helpers do
  include MyAnimeList::Rack::Auth
end


#
# Error handling.
#
error MyAnimeList::NetworkError do
  { :error => "A network error has occurred. Exception message: #{request.env['sinatra.error'].message}" }.to_json
end

error MyAnimeList::UpdateError do
  { :error => "Error updating anime. Exception message: #{request.env['sinatra.error'].message}" }.to_json
end

not_found do
  if response.content_type == JSON_RESPONSE_MIME_TYPE
    { :error => response.body }.to_json
  end
end



# Get an anime's details.
get '/anime/:id' do
  pass unless params[:id] =~ /^\d+$/

  content_type :json

  anime = MyAnimeList::Anime.scrape_anime(params[:id], session['cookie_string'])

  anime.to_json
end

# Updates a user's anime info.
post '/anime/update/:id' do
  pass unless params[:id] =~ /^\d+$/

  # Authenticate with MyAnimeList if we don't have a cookie string.
  authenticate unless session['cookie_string']

  content_type :json

  successful = MyAnimeList::Anime.update(params[:id], session['cookie_string'], {
    :status => params[:status],
    :episodes => params[:episodes],
    :score => params[:score]
  })

  successful ? true.to_json : false.to_json
end

# Get a user's anime list.
get '/animelist/:username' do
  content_type :json

  curl = Curl::Easy.new("http://myanimelist.net/malappinfo.php?u=#{params[:username]}&status=all")
  curl.headers['User-Agent'] = 'MyAnimeList Unofficial API (http://mal-api.com/)'
  begin
    curl.perform
  rescue Exception => e
    raise NetworkError("Network error getting anime list for '#{params[:username]}'. Original exception: #{e.message}.", e)
  end

  case curl.response_code
  when 200

    response = curl.body_str

    # Check for usernames that don't exist. malappinfo.php returns a simple "Invalid username" string (but doesn't
    # return a 404 status code).
    throw :halt, [404, 'User not found'] if response =~ /^invalid username/i

    xml_doc = Nokogiri::XML.parse(response)

    anime_list = xml_doc.search('anime').map do |anime_node|
      anime = MyAnimeList::Anime.new
      anime.id                = anime_node.at('series_animedb_id').text.to_i
      anime.title             = anime_node.at('series_title').text
      anime.type              = anime_node.at('series_type').text
      anime.episodes          = anime_node.at('series_episodes').text.to_i
      anime.watched_episodes  = anime_node.at('my_watched_episodes').text.to_i
      anime.score             = anime_node.at('my_score').text
      anime.watched_status    = anime_node.at('my_status').text

      anime
    end

    return anime_list.to_json

  else
    raise NetworkError("Network error getting anime list for '#{params[:username]}'. MyAnimeList returned HTTP status code #{curl.response_code}.", e)
  end
end

# Search for anime.
get '/anime/search' do
end

# Verify that authentication credentials are valid.
# Returns an HTTP 200 OK response if authentication was successful, or an HTTP 401 response.
get '/auth' do
  # Authenticate with MyAnimeList if we don't have a cookie string.
  authenticate unless session['cookie_string']
end