require 'capistrano/ext/multistage'
require 'bundler/capistrano'

# Used by Capistrano multistage.
set :stages, %w(production staging)

namespace :deploy do
  after 'deploy', 'deploy:cleanup'

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