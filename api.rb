require 'rubygems'
require 'sinatra'
require 'curb'

# Sinatra settings.
set :app_file, __FILE__
set :reload, true


curl = Curl::Easy.new
curl.enable_cookies = true

cookies = []

use Rack::Auth::Basic do |username, password|

  return true if cookies.length > 0

  # Authenticate with MyAnimeList.net.
  # FIXME We should store our own cookie with the user so that auth is not done unnecessarily for all requests.
  curl.url = 'http://myanimelist.net/login.php'

  authenticated = false
  curl.on_header { |header|

    # Parse cookies from the headers (yes, this is a naive implementation but it's fast).
    if header =~ /^Set-Cookie: ([^=])=([^;]+;)/
      cookies << "#{$1}=#{$2}"
    end

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

  authenticated
end


get '/anime' do

  curl.cookies = cookies.join(' ')

  curl.url = 'http://myanimelist.net/panel.php?go=export'
  curl.http_post(
    Curl::PostField.content('type', '1'),
    Curl::PostField.content('subexport', 'Export My List')
  )
  
  curl.body_str
end