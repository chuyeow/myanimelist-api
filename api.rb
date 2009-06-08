require 'rubygems'
require 'sinatra'
require 'curb'
require 'nokogiri'
require 'json'

# Sinatra settings.
set :sessions, true
mime :json, 'text/javascript'

module MyAnimeList
  module Auth

    def auth
      @auth ||= Rack::Auth::Basic::Request.new(request.env)
    end

    def unauthenticated!(realm = 'myanimelist.net')
      headers['WWW-Authenticate'] = %(Basic realm="#{realm}")
      throw :halt, [ 401, 'Authorization Required' ]
    end

    def bad_request!
      throw :halt, [ 400, 'Bad Request' ]
    end

    def authenticated?
      request.env['REMOTE_USER']
    end

    # Authenticate with MyAnimeList.net.
    def authenticate_with_mal(username, password)

      curl = Curl::Easy.new('http://myanimelist.net/login.php')

      authenticated = false
      cookies = []
      curl.on_header { |header|

        # Parse cookies from the headers (yes, this is a naive implementation but it's fast).
        cookies << "#{$1}=#{$2}" if header =~ /^Set-Cookie: ([^=])=([^;]+;)/

        # A HTTP 302 redirection to the MAL panel indicates successful authentication.
        authenticated = true if header =~ %r{^Location: http://myanimelist.net/panel.php\s+}

        header.length
      }
      curl.http_post(
        Curl::PostField.content('username', username),
        Curl::PostField.content('password', password),
        Curl::PostField.content('cookies', '1')
      )

      # Reset the on_header handler.
      curl.on_header

      # Save cookie string into session.
      session['cookie_string'] = cookies.join(' ') if authenticated

      authenticated
    end

    def authenticate
      return if authenticated?
      authenticated! unless auth.provided?
      bad_request! unless auth.basic?
      authenticated! unless authenticate_with_mal(*auth.credentials)
      request.env['REMOTE_USER'] = auth.username
    end
  end
end

helpers do
  include MyAnimeList::Auth
end

before do

  # Authenticate with MyAnimeList if we don't have a cookie string.
  authenticate unless session['cookie_string']

end

get '/anime' do
  content_type :json

  curl = Curl::Easy.new('http://myanimelist.net/panel.php?go=export')
  curl.cookies = session['cookie_string']
  curl.http_post(
    Curl::PostField.content('type', '1'),
    Curl::PostField.content('subexport', 'Export My List')
  )

  html_doc = Nokogiri::HTML(curl.body_str)
  xml_url = html_doc.at('div.goodresult a')['href']

  curl.url = xml_url
  curl.perform

  require 'zlib'
  require 'stringio'

  response = Zlib::GzipReader.new(StringIO.new(curl.body_str)).read
  xml_doc = Nokogiri::XML.parse(response)

  anime_list = xml_doc.search('anime').map do |anime|
    anime.at('series_title').text
  end

  anime_list.to_json
end