set :application, 'myanimelist-api'
set :repository,  "git://github.com/chuyeow/#{application}.git"
set :deploy_to, "/var/rackapps/#{application}"
set :scm, :git
set :deploy_via, :remote_cache
set :use_sudo, false

set :normalize_asset_timestamps, false

server '175.41.136.29', :app, :web, :db
