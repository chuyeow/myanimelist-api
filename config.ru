require 'rubygems'
require 'sinatra'
require 'rewindable_input'

set :environment, :development
set :port, 80

require 'app'

use RewindableInput

run Sinatra::Application