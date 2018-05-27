require 'database_cleaner'

RSpec.configure do |config|
  config.before :suite do
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.clean_with :truncation
  end

  config.before :each do
    DatabaseCleaner.start
    MyConfigPreferences.set_preferences
    Rails.cache.clear
  end

  config.after :each do
    DatabaseCleaner.clean
  end
end
