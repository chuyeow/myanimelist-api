require 'curb'
require 'nokogiri'
require 'json'
require 'activesupport'
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
  { :error => 'network-error', :details => "Exception message: #{request.env['sinatra.error'].message}" }.to_json
end

error MyAnimeList::UpdateError do
  { :error => 'anime-update-error', :details => "Exception message: #{request.env['sinatra.error'].message}" }.to_json
end

error MyAnimeList::UnknownError do
  { :error => 'unknown-error', :details => "Exception message: #{request.env['sinatra.error'].message}" }.to_json
end

error do
  { :error => 'unknown-error', :details => "Exception message: #{request.env['sinatra.error'].message}" }.to_json
end

not_found do
  if response.content_type == JSON_RESPONSE_MIME_TYPE
    { :error => response.body }.to_json
  end
end



# GET /anime/#{anime_id}
# Get an anime's details.
# Optional parameters:
#  * mine=1 - If specified, include the authenticated user's anime details (e.g. user's score, watched status, watched
#             episodes). Requires authentication.
get '/anime/:id' do
  pass unless params[:id] =~ /^\d+$/

  if params[:mine] == '1'
    authenticate unless session['cookie_string']
    anime = MyAnimeList::Anime.scrape_anime(params[:id], session['cookie_string'])
  else
    # FIXME Cache this.
    anime = MyAnimeList::Anime.scrape_anime(params[:id])
  end

  case params[:format]
  when 'xml'
    content_type(:xml)

    anime.to_xml

  else
    content_type(:json)

    anime.to_json
  end
end


# POST /animelist/anime
# Adds an anime to a user's anime list.
post '/animelist/anime' do
  content_type :json

  authenticate unless session['cookie_string']

  # Ensure "anime_id" param is given.
  if params[:anime_id] !~ /\S/
    status 400
    return { :error => 'anime_id-required' }.to_json
  end

  successful = MyAnimeList::Anime.add(params[:anime_id], session['cookie_string'], {
    :status => params[:status],
    :episodes => params[:episodes],
    :score => params[:score]
  })

  if successful
    nil # Return HTTP 200 OK and empty response body if successful.
  else
    status 400
    { :error => 'unknown-error' }.to_json
  end
end


# PUT /animelist/anime/#{anime_id}
# Updates an anime already on a user's anime list.
put '/animelist/anime/:anime_id' do
  content_type :json

  authenticate unless session['cookie_string']

  successful = MyAnimeList::Anime.update(params[:anime_id], session['cookie_string'], {
    :status => params[:status],
    :episodes => params[:episodes],
    :score => params[:score]
  })

  if successful
    nil # Return HTTP 200 OK and empty response body if successful.
  else
    status 400
    { :error => 'unknown-error' }.to_json
  end
end


# DELETE /animelist/anime/#{anime_id}
# Delete an anime from user's anime list.
delete '/animelist/anime/:anime_id' do
  content_type :json

  authenticate unless session['cookie_string']

  anime = MyAnimeList::Anime.delete(params[:anime_id], session['cookie_string'])

  if anime
    anime.to_json # Return HTTP 200 OK and the original anime if successful.
  else
    status 400
    { :error => 'unknown-error' }.to_json
  end
end



# Get a user's anime list.
get '/animelist/:username' do
  content_type :json

  anime_list = MyAnimeList::AnimeList.anime_list_of(params[:username])

  anime_list.to_json
end


# GET /anime/search
# Search for anime.
get '/anime/search' do
  content_type :json

  # Ensure "q" param is given.
  if params[:q] !~ /\S/
    status 400
    return { :error => 'q-required' }.to_json
  end

  authenticate

  results = MyAnimeList::Anime.search(params[:q], :username => auth.username, :password => auth.credentials[1])

  results.to_json
end


# GET /anime/top
# Get the top anime.
get '/anime/top' do
  content_type :json

  anime = MyAnimeList::Anime.top(
    :type     => params[:type],
    :page     => params[:page],
    :per_page => params[:per_page]
  )

  anime.to_json
end


# Verify that authentication credentials are valid.
# Returns an HTTP 200 OK response if authentication was successful, or an HTTP 401 response.
# FIXME This should be rate-limited to avoid brute-force attacks.
get '/account/verify_credentials' do
  # Authenticate with MyAnimeList if we don't have a cookie string.
  authenticate unless session['cookie_string']

  nil # Reponse body is empy.
end