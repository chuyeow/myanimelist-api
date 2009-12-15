require 'rubygems'
require 'vendor/sinatra/lib/sinatra.rb'
require 'vendor/redis/lib/redis.rb'
require 'vendor/redis-store/lib/redis-store.rb'

require 'app'

run Sinatra::Application