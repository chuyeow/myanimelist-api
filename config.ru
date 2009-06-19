require 'rubygems'
require 'sinatra'

set :environment, :development
set :port, 4567

require 'app'

run Sinatra::Application