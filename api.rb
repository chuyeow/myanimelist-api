require 'rubygems'
require 'sinatra'
require 'curb'
require 'tempfile'

curl = Curl::Easy.new
curl.enable_cookies = true

use Rack::Auth::Basic do |username, password|

  # Authenticate with MyAnimeList.net.
  # FIXME We should store our own cookie with the user so that auth is not done unnecessarily for all requests.
  curl.url = 'http://myanimelist.net/login.php'
  tempfile = Tempfile.new('cookies', 'tmp')
  curl.cookiejar = tempfile.path

  authenticated = false
  curl.on_header { |header|
    # A HTTP 302 redirection to the MAL panel indicates successful authentication.
    authenticated = true if header =~ %r{^Location: http://myanimelist.net/panel.php\s+}

    header.length
  }
  curl.http_post(
    Curl::PostField.content('username', username),
    Curl::PostField.content('password', password),
    Curl::PostField.content('cookies', '1')
  )

  # Set the cookiefile for subsequent Curl requests and disable the cookiejar.
  curl.cookiefile = tempfile.path
  curl.cookiejar = nil
  tempfile.close

  # Reset the on_header handler.
  curl.on_header

  authenticated
end


get '/anime' do

  curl.url = 'http://myanimelist.net/panel.php?go=export'
  curl.http_post(
    Curl::PostField.content('type', '1'),
    Curl::PostField.content('subexport', 'Export My List')
  )

  curl.body_str
end