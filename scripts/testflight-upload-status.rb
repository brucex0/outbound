#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "optparse"
require "uri"

STDOUT.sync = true

APP_BUNDLE_ID = "plainstride.outbound"
DEFAULT_KEY_PATH = File.expand_path("~/Library/Application Support/Plainstride/AppStoreConnect/AuthKey_8F64X54A9C.p8")
DEFAULT_KEY_ID = "8F64X54A9C"
DEFAULT_ISSUER_ID = "fe8791ac-9cbb-424a-8491-233753db92a7"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: #{$PROGRAM_NAME} --latest | --version VERSION --build-number NUMBER [--delete-awaiting ID]"
  parser.on("--latest", "List recent uploads and builds without changing them") { options[:latest] = true }
  parser.on("--version VERSION", "Marketing version to inspect") { |value| options[:version] = value }
  parser.on("--build-number NUMBER", "Build number to inspect") { |value| options[:build] = value }
  parser.on("--delete-awaiting ID", "Delete only this exact pending upload after all uploaders have stopped") do |value|
    options[:delete_id] = value
  end
  parser.on("--fail-if-build-exists", "Fail if App Store Connect already has this build") do
    options[:fail_if_build_exists] = true
  end
  parser.on("-h", "--help", "Show help") { puts parser; exit }
end.parse!

abort "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
if options[:latest]
  abort "--latest cannot be combined with a version, build, or delete option" if options[:version] || options[:build] || options[:delete_id]
else
  abort "--version and --build-number are required" unless options[:version]&.match?(/\A\d+(?:\.\d+){0,2}\z/) && options[:build]&.match?(/\A\d+\z/)
end
if options[:delete_id] && !options[:delete_id].match?(/\A[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z/)
  abort "--delete-awaiting requires an exact upload UUID"
end

key_path = ENV.fetch("ASC_KEY_PATH", DEFAULT_KEY_PATH)
key_id = ENV.fetch("ASC_KEY_ID", DEFAULT_KEY_ID)
issuer_id = ENV.fetch("ASC_ISSUER_ID", DEFAULT_ISSUER_ID)
abort "App Store Connect API key is unavailable: #{key_path}" unless File.readable?(key_path)

base64url = ->(value) { Base64.urlsafe_encode64(value).delete("=") }
now = Time.now.to_i
header = { alg: "ES256", kid: key_id, typ: "JWT" }
claims = { iss: issuer_id, iat: now, exp: now + 900, aud: "appstoreconnect-v1" }
signing_input = "#{base64url.call(JSON.generate(header))}.#{base64url.call(JSON.generate(claims))}"
key = OpenSSL::PKey::EC.new(File.read(key_path))
sequence = OpenSSL::ASN1.decode(key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input)))
signature = sequence.value.map do |integer|
  hex = integer.value.to_i.to_s(16).rjust(64, "0")
  abort "unexpected App Store Connect signature size" if hex.length > 64
  [hex].pack("H*")
end.join
token = "#{signing_input}.#{base64url.call(signature)}"

request = lambda do |method, path, query = {}|
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  uri.query = URI.encode_www_form(query) unless query.empty?
  request_class = method == :delete ? Net::HTTP::Delete : Net::HTTP::Get
  http_request = request_class.new(uri)
  http_request["Authorization"] = "Bearer #{token}"
  http_request["Accept"] = "application/json"
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
    http.request(http_request)
  end
  unless response.is_a?(Net::HTTPSuccess)
    error_body = JSON.parse(response.body) rescue {}
    detail = error_body.fetch("errors", []).map { |error| error["detail"] || error["title"] }.join("; ")
    abort "App Store Connect #{method.to_s.upcase} #{path}: HTTP #{response.code} #{detail}".strip
  end
  response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
end

apps = request.call(:get, "/v1/apps", { "filter[bundleId]" => APP_BUNDLE_ID, "limit" => 2 }).fetch("data")
abort "expected one app for #{APP_BUNDLE_ID}, found #{apps.length}" unless apps.length == 1
app_id = apps.first.fetch("id")
if options[:latest]
  recent_uploads = request.call(:get, "/v1/apps/#{app_id}/buildUploads", {
    "fields[buildUploads]" => "cfBundleShortVersionString,cfBundleVersion,createdDate,state,uploadedDate",
    "sort" => "-uploadedDate",
    "limit" => 200
  }).fetch("data")
  puts "Recent upload records:"
  recent_uploads.sort_by { |upload| upload.dig("attributes", "createdDate").to_s }.reverse.first(10).each do |upload|
    attributes = upload.fetch("attributes")
    puts "  #{attributes['cfBundleShortVersionString']} (#{attributes['cfBundleVersion']}): #{attributes.dig('state', 'state')} | #{attributes['createdDate']} | #{upload['id']}"
  end
  recent_builds = request.call(:get, "/v1/builds", {
    "filter[app]" => app_id,
    "fields[builds]" => "version,processingState,uploadedDate",
    "sort" => "-uploadedDate",
    "limit" => 10
  }).fetch("data")
  puts "Recent build records:"
  recent_builds.each do |build|
    attributes = build.fetch("attributes")
    puts "  #{attributes['version']}: #{attributes['processingState']} | #{attributes['uploadedDate']}"
  end
  exit
end

builds = request.call(:get, "/v1/builds", {
  "filter[app]" => app_id,
  "filter[version]" => options[:build],
  "filter[preReleaseVersion.version]" => options[:version],
  "fields[builds]" => "version,processingState,uploadedDate",
  "limit" => 2
}).fetch("data")
abort "multiple builds match #{options[:version]} (#{options[:build]})" if builds.length > 1

uploads_response = request.call(:get, "/v1/apps/#{app_id}/buildUploads", {
  "filter[cfBundleVersion]" => options[:build],
  "filter[cfBundleShortVersionString]" => options[:version],
  "fields[buildUploads]" => "cfBundleShortVersionString,cfBundleVersion,createdDate,state,uploadedDate,assetFile,assetDescriptionFile,assetSpiFile",
  "include" => "assetFile,assetDescriptionFile,assetSpiFile",
  "fields[buildUploadFiles]" => "assetDeliveryState,assetType,fileName,fileSize",
  "limit" => 200
})
uploads = uploads_response.fetch("data")
files = uploads_response.fetch("included", []).to_h { |file| [file.fetch("id"), file] }

puts "Plainstride #{options[:version]} (#{options[:build]})"
if builds.empty?
  puts "Build record: none"
else
  attributes = builds.first.fetch("attributes")
  puts "Build record: #{attributes['processingState']} (uploaded #{attributes['uploadedDate']})"
end
if uploads.empty?
  puts "Upload records: none"
else
  uploads.each do |upload|
    attributes = upload.fetch("attributes")
    puts "Upload #{upload.fetch('id')}: #{attributes.dig('state', 'state')} (created #{attributes['createdDate']})"
    %w[assetDescriptionFile assetSpiFile assetFile].each do |relationship|
      id = upload.dig("relationships", relationship, "data", "id")
      next unless id
      file = files[id]
      next unless file
      file_attributes = file.fetch("attributes")
      puts "  #{file_attributes['assetType']}: #{file_attributes.dig('assetDeliveryState', 'state')} (#{file_attributes['fileSize']} bytes)"
    end
  end
end

if options[:delete_id]
  abort "build already exists; refusing to delete its upload" unless builds.empty?
  abort "expected exactly one matching upload" unless uploads.length == 1
  upload = uploads.first
  abort "upload ID does not match" unless upload.fetch("id") == options[:delete_id]
  abort "only AWAITING_UPLOAD records can be deleted" unless upload.dig("attributes", "state", "state") == "AWAITING_UPLOAD"
  abort "app binary is already attached; refusing to delete" if upload.dig("relationships", "assetFile", "data", "id")
  abort "altool is still running; stop it before deleting the upload" if system("pgrep", "-x", "altool", out: File::NULL, err: File::NULL)
  request.call(:delete, "/v1/buildUploads/#{options[:delete_id]}")
  puts "Deleted pending upload #{options[:delete_id]}. The next upload can create a fresh reservation."
end

if options[:fail_if_build_exists] && !builds.empty?
  abort "build already exists; use publish-testflight.sh --setup-only instead of uploading again"
end
