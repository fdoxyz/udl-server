require 'sinatra'
if !production?
  require 'sinatra/reloader'
  require 'dotenv/load'
  require 'byebug'
end

require 'uri'
require 'json'
require 'redis-activesupport'
require 'rack/attack'

Rack::Attack.cache.store = ActiveSupport::Cache.lookup_store :redis_store

if ENV['UDL_THROTTLE_LIMIT'].present? && ENV['UDL_THROTTLE_PERIOD'].present?
  limit = ENV['UDL_THROTTLE_LIMIT'].to_i
  period = ENV['UDL_THROTTLE_PERIOD'].to_i
  Rack::Attack.throttle('requests/ip', limit: limit, period: period) do |request|
    request.ip
  end
end

if ENV['UDL_SAFELIST_REGEXP'].present?
  safelist_regexp = Regexp.new(ENV['UDL_SAFELIST_REGEXP'])
  Rack::Attack.safelist("allow safelist") do |request|
    # Requests will be safelisted if the 'r' param matches the regexp
    request.params["r"] =~ safelist_regexp
  end
end

if ENV['UDL_BLOCKLIST_REGEXP'].present?
  blocklist_regexp = Regexp.new(ENV['UDL_BLOCKLIST_REGEXP'])
  Rack::Attack.blocklist("deny blocklist") do |request|
    # Requests will be blocklisted if the 'r' param matches the regexp
    request.params["r"] =~ blocklist_regexp
  end
end

get '/' do
  begin
    redirect URI(params[:r])
  rescue => error
    @error = error
    logger.info @error.inspect
    erb :fallback
  end
end

get '/.well-known/apple-app-site-association' do
  content_type :json
  {
    "applinks": {
      "apps": [],
      "details":[
        {
          "appID": ENV['AASA_APP_ID'].to_s,
          "paths": ["/*"]
        }
      ]
    }
  }.to_json
end

get '/*' do
  begin
    target_url = URI(params['splat'].first)
    raise 'Invalid redirect URL' if target_url.host != request.host
    redirect target_url
  rescue => error
    @error = error
    logger.info @error.inspect
    erb :fallback
  end
end