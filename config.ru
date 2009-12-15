require 'rubygems'

# Add vendored gems' lib/ directories to the load path.
%w(sinatra redis redis-store).each do |gem_name|
  $LOAD_PATH.unshift(File.expand_path(File.join(File.dirname(__FILE__), 'vendor', gem_name, 'lib')))
end

require 'app'

run App