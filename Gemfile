source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.6.1'

#--------------------------------------------------------------------------------------------------
# Core
gem 'rails', '~> 6.0'
gem 'rake', '~> 13.0'
gem 'mongoid', '~> 7.0.5'
# https://github.com/mongoid/mongoid-locker
gem 'mongoid-locker', '~>2.0'

gem 'puma', '~> 4.2'                       # Use Puma for the web server

gem 'aws-sdk', '~>3.0'

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
gem 'rack-cors', require: 'rack/cors'

# https://www.rubydoc.info/gems/resque/2.0.0
# gem 'resque', '~>2.0'

gem 'nokogiri', '~> 1.10'

# https://github.com/adzap/timeliness
gem 'timeliness', '~>0.4.3'                 # Date and Time parsing
gem 'timeliness-i18n', '~>0.7'              # I18n translations

# https://github.com/adzap/validates_timeliness
gem 'validates_timeliness', '~>4.1'           # Date and Time validation

# https://github.com/dgilperez/validates_zipcode
gem 'validates_zipcode', '~> 0.2'             # Zipcode validation

# https://github.com/rails/jbuilder
# gem 'jbuilder', '~> 2.7.0'                  # Build JSON APIs
# gem 'sdoc', '~> 1.0.0', group: :doc         # bundle exec rake doc:rails generates the API under doc/api.

# https://github.com/Shopify/bootsnap -- load performance improvement
gem 'bootsnap', '>= 1.4', require: false

#--------------------------------------------------------------------------------------------------
# AuthN / AuthZ
gem 'bcrypt', '~> 3.1.13'                   # Use ActiveModel has_secure_password
gem 'jwt', '~>2.2'                          # Use JSON Web Tokens

# https://github.com/ambethia/recaptcha
gem 'recaptcha', '~>5.1'                    # Use reCAPTCHA

# https://stripe.com/
gem 'stripe', '~>5.2'                       # Use Stripe for billing

# https://github.com/integrallis/stripe_event
gem 'stripe_event', '~>2.3'                  # Engine-level webhook responder

# https://github.com/nathanl/authority
# https://www.rubydoc.info/gems/authority/3.3.0
gem 'authority', git: 'https://github.com/brendandixon/authority.git' # Use Authority for authZ

#--------------------------------------------------------------------------------------------------
# Development / Test
group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]

  # https://github.com/colszowka/simplecov
  gem 'simplecov'                           # Code coverage
  gem 'simplecov-lcov'

  # https://github.com/bkeepers/dotenv
  gem 'dotenv'                              # Load .env file into ENV in development / test mode

  # https://www.rubydoc.info/gems/factory_bot/file/README.md
  gem 'factory_bot_rails', '~> 5.1'         # Use FactoryBot for seeds and what not
end

group :development do
  gem 'listen', '>= 3.0.5', '< 3.2'

  gem 'foreman'

  # https://github.com/rspec/rspec-expectations
  # http://rspec.info/documentation/
  # http://www.rubydoc.info/gems/rspec-rails/file/README.md
  gem 'rspec', '~> 3.8.0'                   # Use Rspec for testing, see http://rspec.info/
  gem 'rspec-rails', '~> 3.8.0'             # See https://relishapp.com/rspec/rspec-rails/v/3-4/docs
  gem 'rspec-activemodel-mocks', '~>1.1'    # See https://github.com/rspec/rspec-activemodel-mocks/
  gem 'spring-commands-rspec', '~>1.0.4'    # Enable Spring optimized loads for Rspec
  
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring', '~> 2.1'
  gem 'spring-watcher-listen', '~> 2.0'
  gem 'rails-controller-testing', '~>1.0.2'

  # http://www.ultrahook.com
  gem 'ultrahook', '~>0.1.5'                # Webhook forwarding service
end
