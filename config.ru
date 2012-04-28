require 'rubygems'
require 'bundler'

Bundler.require

dalli_config = YAML.load(IO.read(File.join('config', 'dalli.yml')))[ENV['RACK_ENV']]

use Rack::Cache,
  :metastore => "memcached://#{dalli_config[:server]}/meta",
  :entitystore => "memcached://#{dalli_config[:server]}/body",
  :default_ttl => dalli_config[:expires_in]

require './app'
run App