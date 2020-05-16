# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
ENV["upload_provider"] = "file"

require "simplecov"
if ENV["CI"] == "true"
  require "codecov"
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
end
SimpleCov.start "rails"

require_relative "../config/environment"
require "minitest/autorun"
require "mocha/minitest"
require "rails/test_help"
require "sidekiq/testing"


FileUtils.mkdir_p(Rails.root.join("tmp/cache"))


OmniAuth.config.test_mode = true
Devise.stretches = 1
Rails.logger.level = 4
FactoryBot.use_parent_strategy = false

ActiveRecord::Base.connection.create_table(:monkeys, force: true) do |t|
  t.string :name
  t.integer :user_id
  t.integer :comments_count
  t.timestamps null: false
end

ActiveRecord::Base.connection.create_table(:commentable_pages, force: true) do |t|
  t.string :name
  t.integer :user_id
  t.integer :comments_count, default: 0, null: false
  t.timestamps null: false
end

class CommentablePage < ApplicationRecord
end

class Monkey < ApplicationRecord
end

class ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  # parallelize(workers: 2)

  setup do
    Setting.stubs(:topic_create_limit_interval).returns("")
    Setting.stubs(:topic_create_hour_limit_count).returns("")
  end

  teardown do
    Rails.cache.clear
  end

  def read_file(fname)
    load_file(fname).read.strip
  end

  def load_file(fname)
    File.open(Rails.root.join("test", "fixtures", fname))
  end

  def assert_html_equal(excepted, html)
    assert_equal excepted.strip.gsub(/>[\s]+</, "><"), html.strip.gsub(/>[\s]+</, "><")
  end

  def assert_has_keys(collection, *keys)
    keys.each do |key|
      assert_equal true, collection.has_key?(key)
    end
  end

  def assert_includes_all(collection, *other)
    other.each do |item|
      assert_includes collection, item
    end
  end

  def assert_not_includes_any(collection, *other)
    other.each do |item|
      assert_not_includes collection, item
    end
  end

  def fixture_file_upload(name, content_type = "text/plain")
    Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/#{name}"), content_type)
  end
end

class ActionView::TestCase
  def sign_in(user)
    @user = user
  end

  def sign_out
    @user = nil
  end

  def current_user; @user; end
end


class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def assert_require_user(&block)
    yield block
    assert_equal 302, response.status
    assert_match /\/account\/sign_in/, response.headers["Location"]
  end
end

# require_relative "./sql_log"

module SqlSource
  class << self
    attr_accessor :current_tag
    attr_accessor :dest, :bc

    def find_source(trace)
      return @bc.clean(trace)[-1]
    end

    def find_spec(trace)
      index = trace.rindex { |x|
        x.include? "_test.rb"
      }
      return nil if index.nil?
      return trace[index].scan(/(?:.*\/)(.*?\w*?_test\.rb:[0-9]*)/)[0][0]
    end

    def register_sql(trace, sql)
      source = self.find_source(trace)
      spec = self.find_spec(trace)
      return unless (not source.nil? and not sql.nil? and not spec.nil?)
      tag = "#{source} !!! #{spec}"
      if tag != @current_tag
        if not @current_tag.nil?
          @dest.puts("-#@current_tag")
        end
        @dest.puts("+#{tag}")
        @current_tag = tag
      end
      @dest.puts("|>#{sql}")
    end

    def close()
      puts "closing"
      return unless not @current_tag.nil?
      @dest.puts("-#@current_tag")
      # @dest.close
    end
  end
end

SqlSource.dest = File.new(Rails.root.join("sql.logs"), "a")
puts Rails.root.join("sql.logs")
puts SqlSource.dest
SqlSource.bc = ActiveSupport::BacktraceCleaner.new
SqlSource.bc.add_filter { |line| line.gsub(Rails.root.to_s, '') }
SqlSource.bc.add_silencer { |line| line =~ /\.rvm|_test/ }

END {
  SqlSource.close
}

ActiveSupport::Notifications.subscribe "sql.active_record" do |*args|
  event = ActiveSupport::Notifications::Event.new *args

  unless event.payload[:cached]
    SqlSource.register_sql(caller, event.payload[:sql])
  end
end
