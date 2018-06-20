require 'rubygems'
require 'bundler'
require 'sinatra'
require 'dotenv'
require 'json'
require 'sinatra/json'
require 'slack'

Bundler.require

Dotenv.load

Slack.configure do |config|
    config.token = ENV["SLACK_API_TOKEN"]
end

# Library files
Dir[File.dirname(__FILE__) + '/*.rb'].each {|file| require file }
