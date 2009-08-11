require 'curb'
require 'nokogiri'
require 'json'
require 'my_anime_list'


# Sinatra settings.
set :sessions, true
JSON_RESPONSE_MIME_TYPE = 'application/json'
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
# Optional parameters:
#  * mine=1 - If specified, include the authenticated user's anime details (e.g. user's score, watched status, watched
#             episodes). Requires authentication.
get '/anime/:id' do
  pass unless params[:id] =~ /^\d+$/

  content_type :json

  if params[:mine] == '1'
    authenticate unless session['cookie_string']
    anime = MyAnimeList::Anime.scrape_anime(params[:id], session['cookie_string'])
  else
    # FIXME Cache this.
    anime = MyAnimeList::Anime.scrape_anime(params[:id])
  end

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

  anime_list = MyAnimeList::AnimeList.anime_list_of(params[:username])

  anime_list.to_json
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