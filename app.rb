require 'sinatra/base'
require 'redis-store'

require 'rubygems'
require 'curb'
require 'net/http'
require 'nokogiri'
require 'builder'
require 'json'
require 'my_anime_list'


class App < Sinatra::Base

  configure do
    enable :sessions, :static
    disable :raise_errors
    set :public, Proc.new { File.join(File.dirname(__FILE__), 'public') }
  end

  JSON_RESPONSE_MIME_TYPE = 'application/json'
  mime_type :json, JSON_RESPONSE_MIME_TYPE

  # Error handlers.
  not_found do
    if response.content_type == JSON_RESPONSE_MIME_TYPE
      { :error => response.body }.to_json
    else
      "<error><code>#{response.body}</code></error>"
    end
  end

  error MyAnimeList::NetworkError do
    details = "Exception message: #{request.env['sinatra.error'].message}"
    case params[:format]
    when 'xml'
      "<error><code>network-error</code><details>#{details}</details></error>"
    else
      { :error => 'network-error', :details => details }.to_json
    end
  end

  error MyAnimeList::UpdateError do
    details = "Exception message: #{request.env['sinatra.error'].message}"
    case params[:format]
    when 'xml'
      "<error><code>anime-update-error</code><details>#{details}</details></error>"
    else
      { :error => 'anime-update-error', :details => details }.to_json
    end
  end

  error MyAnimeList::NotFoundError do
    case params[:format]
    when 'xml'
      halt 404, "<error><code>not-found</code><details>#{request.env['sinatra.error'].message}</details></error>"
    else
      halt 404, { :error => 'not-found', :details => request.env['sinatra.error'].message }.to_json
    end
  end

  error MyAnimeList::UnknownError do
    details = "Exception message: #{request.env['sinatra.error'].message}"
    case params[:format]
    when 'xml'
      "<error><code>unknown-error</code><details>#{details}</details></error>"
    else
      { :error => 'unknown-error', :details => details }.to_json
    end
  end

  error do
    details = "Exception message: #{request.env['sinatra.error'].message}"
    case params[:format]
    when 'xml'
      "<error><code>unknown-error</code><details>#{details}</details></error>"
    else
      { :error => 'unknown-error', :details => details }.to_json
    end
  end


  helpers do
    include MyAnimeList::Rack::Auth
  end

  before do
    case params[:format]
    when 'xml'
      content_type(:xml)
    else
      content_type(:json)
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
      anime.to_xml
    else
      anime.to_json
    end
  end


  # POST /animelist/anime
  # Adds an anime to a user's anime list.
  post '/animelist/anime' do
    authenticate unless session['cookie_string']

    # Ensure "anime_id" param is given.
    if params[:anime_id] !~ /\S/
      case params[:format]
      when 'xml'
        halt 400, '<error><code>anime_id-required</code></error>'
      else
        halt 400, { :error => 'anime_id-required' }.to_json
      end
    end

    successful = MyAnimeList::Anime.add(params[:anime_id], session['cookie_string'], {
      :status => params[:status],
      :episodes => params[:episodes],
      :score => params[:score]
    })

    if successful
      nil # Return HTTP 200 OK and empty response body if successful.
    else
      case params[:format]
      when 'xml'
        halt 400, '<error><code>unknown-error</code></error>'
      else
        halt 400, { :error => 'unknown-error' }.to_json
      end
    end
  end


  # PUT /animelist/anime/#{anime_id}
  # Updates an anime already on a user's anime list.
  put '/animelist/anime/:anime_id' do
    authenticate unless session['cookie_string']

    successful = MyAnimeList::Anime.update(params[:anime_id], session['cookie_string'], {
      :status => params[:status],
      :episodes => params[:episodes],
      :score => params[:score]
    })

    if successful
      nil # Return HTTP 200 OK and empty response body if successful.
    else
      case params[:format]
      when 'xml'
        halt 400, '<error><code>unknown-error</code></error>'
      else
        halt 400, { :error => 'unknown-error' }.to_json
      end
    end
  end


  # DELETE /animelist/anime/#{anime_id}
  # Delete an anime from user's anime list.
  delete '/animelist/anime/:anime_id' do
    authenticate unless session['cookie_string']

    anime = MyAnimeList::Anime.delete(params[:anime_id], session['cookie_string'])

    if anime
      case params[:format]
      when 'xml'
        anime.to_xml
      else
        anime.to_json # Return HTTP 200 OK and the original anime if successful.
      end
    else
      case params[:format]
      when 'xml'
        halt 400, '<error><code>unknown-error</code></error>'
      else
        halt 400, { :error => 'unknown-error' }.to_json
      end
    end
  end


  # GET /animelist/#{username}
  # Get a user's anime list.
  get '/animelist/:username' do
    anime_list = MyAnimeList::AnimeList.anime_list_of(params[:username])

    case params[:format]
    when 'xml'
      anime_list.to_xml
    else
      anime_list.to_json
    end
  end


  # GET /anime/search
  # Search for anime.
  get '/anime/search' do
    # Ensure "q" param is given.
    if params[:q] !~ /\S/
      case params[:format]
      when 'xml'
        halt 400, '<error><code>q-required</code></error>'
      else
        halt 400, { :error => 'q-required' }.to_json
      end
    end

    results = MyAnimeList::Anime.search(params[:q])

    case params[:format]
    when 'xml'
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct!

      xml.results do |xml|
        xml.query params[:q]
        xml.count results.size

        results.each do |a|
          xml << a.to_xml(:skip_instruct => true)
        end
      end

      xml.target!
    else
      results.to_json
    end
  end


  # GET /anime/top
  # Get the top anime.
  get '/anime/top' do
    anime = MyAnimeList::Anime.top(
      :type     => params[:type],
      :page     => params[:page],
      :per_page => params[:per_page]
    )

    case params[:format]
    when 'xml'
      anime.to_xml
    else
      anime.to_json
    end
  end


  # GET /history/#{username}
  # Get user's history.
  # FIXME implement /history/:username/anime and /history/:username/manga - use regex for routing?
  get '/history/:username' do
    user = MyAnimeList::User.new
    user.username = params[:username]

    history = user.history

    case params[:format]
    when 'xml'
      history.to_xml
    else
      history.to_json
    end
  end


  # GET /mangalist/#{username}
  # Get a user's manga list.
  get '/mangalist/:username' do
    manga_list = MyAnimeList::MangaList.manga_list_of(params[:username])

    case params[:format]
    when 'xml'
      manga_list.to_xml
    else
      manga_list.to_json
    end
  end


  # Verify that authentication credentials are valid.
  # Returns an HTTP 200 OK response if authentication was successful, or an HTTP 401 response.
  # FIXME This should be rate-limited to avoid brute-force attacks.
  get '/account/verify_credentials' do
    # Authenticate with MyAnimeList if we don't have a cookie string.
    authenticate unless session['cookie_string']

    nil # Reponse body is empy.
  end
end