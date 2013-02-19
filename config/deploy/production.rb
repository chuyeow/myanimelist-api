set :application, 'myanimelist-api'
set :repository,  'git://github.com/chuyeow/myanimelist-api.git'
set :deploy_to, '/var/apps/myanimelist-api'
set :scm, :git
set :deploy_via, :remote_cache

set :user, 'deploy'
set :runner, 'deploy'
set :use_sudo, false

set :normalize_asset_timestamps, false

server '198.211.96.88', :app, :web, :db

ssh_options[:port] = 3456
ssh_options[:forward_agent] = true
default_run_options[:pty] = true

namespace :deploy do

  desc 'Copy various config files from shared directory into current release directory.'
  task :post_update_code, :roles => :app do
    configs = %w(dalli.yml)
    config_paths = configs.map { |config| "#{shared_path}/config/#{config}" }
    run "cp #{config_paths.join(' ')} #{release_path}/config/"
  end
  after 'deploy:update_code', 'deploy:post_update_code'

end