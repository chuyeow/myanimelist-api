set :application, 'myanimelist-api'
set :repository,  'git://github.com/chuyeow/myanimelist-api.git'
set :deploy_to, '/var/rackapps/myanimelist-api'
set :scm, :git
set :deploy_via, :remote_cache

set :user, 'deploy'
set :runner, 'deploy'
set :use_sudo, false

set :normalize_asset_timestamps, false

server 'mal-api.com', :app, :web, :db
