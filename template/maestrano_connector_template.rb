def current_directory
  @current_directory ||=
    if __FILE__ =~ %r{\Ahttps?://}
      tempdir = Dir.mktmpdir('maestrano-connector-rails-')
      at_exit { FileUtils.remove_entry(tempdir) }
      git clone: "--quiet https://github.com/maestrano/maestrano-connector-rails/ #{tempdir}"

      "#{tempdir}/template"
    else
      File.expand_path(File.dirname(__FILE__))
    end
end

# def current_directory
#   File.expand_path(File.dirname(__FILE__))
# end

# Add the current directory to the path Thor uses
# to look up files
def source_paths
  Array(super) + [current_directory]
end

#
# Rebuild the Gemfile from scratch
#
remove_file 'Gemfile'
run 'touch Gemfile'

add_source 'https://rubygems.org'
if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
  run 'echo "ruby \'2.3.1\', :engine => \'jruby\', :engine_version => \'9.1.5.0\'" | cat - Gemfile > temp && mv temp Gemfile'
end

gem 'rails', '~> 4.2'
gem 'turbolinks', '~> 2.5'
gem 'jquery-rails'
gem 'tzinfo-data', platforms: [:mingw, :mswin, :jruby]
gem 'uglifier', '>= 1.3.0'

gem 'puma', require: false
gem 'sinatra', require: false
gem 'sidekiq'
gem 'sidekiq-cron'

gem 'maestrano-connector-rails'

gem_group :production, :uat do
  gem 'activerecord-jdbcmysql-adapter', platforms: :jruby
  gem 'mysql2', platforms: :ruby
  gem 'rails_12factor'
end

gem_group :test, :development do
  gem 'activerecord-jdbcsqlite3-adapter', platforms: :jruby
  gem 'sqlite3', platforms: :ruby
  gem 'rubocop'
end

gem_group :test do
  gem 'simplecov'
  gem 'rspec-rails'
  gem 'factory_girl_rails'
  gem 'shoulda-matchers'
  gem 'timecop'
end

remove_file '.gitignore'
copy_file 'gitignore', '.gitignore'
copy_file 'rubocop.yml', '.rubocop.yml'

#
# Cleanup
#
after_bundle do
  remove_dir 'app/mailers'
  remove_dir 'test'
  remove_file 'app/views/layouts/application.html.erb'
  remove_file 'app/assets/stylesheets/application.css'
  remove_file 'config/routes.rb'
  copy_file 'spec_helper.rb', 'spec/spec_helper.rb'
  copy_file 'routes.rb', 'config/routes.rb'

  # Heroku and uat
  copy_file 'Procfile', 'Procfile'
  run 'cp config/environments/production.rb config/environments/uat.rb'
  remove_file 'config/database.yml'
  copy_file 'database.yml', 'config/database.yml'
  run 'echo \'uat:
  secret_key_base: <%= ENV["SECRET_KEY_BASE"] %>\' >> config/secrets.yml'

  # Sidekiq
  copy_file 'sidekiq.yml', 'config/sidekiq.yml'
  copy_file 'sidekiq.rb', 'config/initializers/sidekiq.rb'

  # Settings
  run 'bundle exec rails g config:install'
  remove_dir 'config/settings'
  remove_file 'config/settings.yml'
  run 'mkdir config/settings'
  %w(development production test uat).each do |file|
    copy_file "settings/#{file}.yml", "config/settings/#{file}.yml"
  end
  copy_file 'settings/settings.yml', 'config/settings.yml'

  copy_file 'application-sample.yml', 'config/application-sample.yml'
  copy_file 'application-sample.yml', 'config/application.yml', force: true

  application do
    <<-RUBY
      config.generators do |g|
        g.test_framework :rspec, fixture: false
        g.view_specs false
        g.helper_specs false
      end
    RUBY
  end

  run 'bundle exec rails g connector:install'
  run 'bundle exec figaro install'
  run 'bundle exec rake railties:install:migrations'
  run 'bundle exec rake db:migrate'

  run 'bundler binstubs puma --force'
  run 'bundler binstubs sidekiq --force'
  run 'bundler binstubs rake --force'

  remove_file 'config/initializers/maestrano.rb'
  copy_file 'maestrano.rb', 'config/initializers/maestrano.rb'

  # Init repo and commit
  git :init
  git add: '.'
  git commit: "-a -m 'Initial commit'"
end
