require 'rubygems'
require 'sinatra'

set :environment, :development
set :port, 80

require 'app'

run Sinatra::Application