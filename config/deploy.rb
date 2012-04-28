require 'capistrano/ext/multistage'
require 'bundler/capistrano'

# Used by Capistrano multistage.
set :stages, %w(production staging)

namespace :deploy do
  after 'deploy:update_code', 'deploy:post_update_code'
  after 'deploy', 'deploy:cleanup'

  task :post_update_code, :roles => :app do

    # Copy config files from shared directory into current release directory.
    configs = %w(dalli.yml)
    config_paths = configs.map { |config| "#{shared_path}/config/#{config}" }
    run "cp #{config_paths.join(' ')} #{release_path}/config/"
  end

  desc "Start application"
  task :start, :roles => :app do
    run "touch #{current_release}/tmp/restart.txt"
  end

  task :stop, :roles => :app do
    # Do nothing.
  end

  desc "Restart application"
  task :restart, :roles => :app do
    run "touch #{current_release}/tmp/restart.txt"
  end
end