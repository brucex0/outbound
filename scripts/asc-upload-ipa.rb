#!/usr/bin/env ruby
# frozen_string_literal: true

# Apple's Build Upload API accepts the signed IPA directly. Keep upload URLs and
# authorization headers in memory; the on-disk checkpoint contains no secrets.
require "base64"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "openssl"
require "optparse"
require "time"
require "uri"

STDOUT.sync = true

class PublishError < StandardError; end
class RetryableResponse < StandardError; end

class ASCUpload
  DEFAULT_KEY_PATH = File.expand_path("~/Library/Application Support/Plainstride/AppStoreConnect/AuthKey_8F64X54A9C.p8")
  TRANSIENT_HTTP = [408, 429, 500, 502, 503, 504].freeze
  NETWORK_ERRORS = [SocketError, Timeout::Error, EOFError, IOError, SystemCallError, OpenSSL::SSL::SSLError].freeze

  def initialize(options)
    @options = options
    @key_path = ENV.fetch("ASC_KEY_PATH", DEFAULT_KEY_PATH)
    @key_id = ENV.fetch("ASC_KEY_ID", "8F64X54A9C")
    @issuer_id = ENV.fetch("ASC_ISSUER_ID", "fe8791ac-9cbb-424a-8491-233753db92a7")
    @state = {}
  end

  def log(message)
    now = Time.now
    puts "[#{now.strftime('%H:%M:%S')}] #{message}"
    if @events_path
      File.open(@events_path, File::WRONLY | File::APPEND | File::CREAT, 0o600) do |events|
        events.puts JSON.generate(time: now.utc.iso8601, message: message)
      end
    end
  end

  def save
    @state["updated_at"] = Time.now.utc.iso8601
    temporary = "#{@state_path}.tmp"
    File.write(temporary, JSON.pretty_generate(@state) + "\n", perm: 0o600)
    File.rename(temporary, @state_path)
  end

  def jwt
    now = Time.now.to_i
    encode = ->(value) { Base64.urlsafe_encode64(value, padding: false) }
    input = [encode.call(JSON.generate(alg: "ES256", kid: @key_id, typ: "JWT")),
             encode.call(JSON.generate(iss: @issuer_id, iat: now, exp: now + 900, aud: "appstoreconnect-v1"))].join(".")
    key = OpenSSL::PKey::EC.new(File.read(@key_path))
    integers = OpenSSL::ASN1.decode(key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(input))).value
    signature = integers.map { |integer| [integer.value.to_i.to_s(16).rjust(64, "0")].pack("H*") }.join
    "#{input}.#{encode.call(signature)}"
  end

  def api(method, path, payload: nil, query: {}, allow_missing: false)
    uri = URI("https://api.appstoreconnect.apple.com#{path}")
    uri.query = URI.encode_www_form(query) unless query.empty?
    attempts = 0
    begin
      attempts += 1
      request = Net::HTTP.const_get(method.capitalize).new(uri)
      request["Authorization"] = "Bearer #{jwt}"
      request["Accept"] = "application/json"
      if payload
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
      end
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60, write_timeout: 60) do |http|
        http.max_retries = 0
        http.request(request)
      end
      return nil if allow_missing && response.code == "404"
      unless response.is_a?(Net::HTTPSuccess)
        raise RetryableResponse, "HTTP #{response.code}" if method == "GET" && TRANSIENT_HTTP.include?(response.code.to_i)
        errors = JSON.parse(response.body).fetch("errors", []) rescue []
        details = errors.map { |error| [error["code"], error["detail"] || error["title"]].compact.join(": ") }.join("; ")
        raise PublishError, "API #{method} #{path}: HTTP #{response.code} #{details}"
      end
      response.body.to_s.empty? ? {} : JSON.parse(response.body)
    rescue RetryableResponse, *NETWORK_ERRORS => error
      if method == "GET" && attempts < 4
        context = error.is_a?(RetryableResponse) ? error.message : error.class.to_s
        log "API #{method} #{path}: #{context}; retry #{attempts}/3"
        sleep [2**attempts, 10].min
        retry
      end
      # Never blindly retry a creation after an unknown response. The next run
      # reconciles the matching upload/file records before creating anything.
      context = error.is_a?(RetryableResponse) ? error.message : error.class.to_s
      raise PublishError, "API #{method} #{path}: #{context}; response unknown, rerun the same command to reconcile"
    end
  end

  def plist(ipa, entry)
    bytes, _, status = Open3.capture3("unzip", "-p", ipa, entry)
    raise PublishError, "Cannot read packaged plist: #{entry}" unless status.success?
    json, _, status = Open3.capture3("plutil", "-convert", "json", "-o", "-", "--", "-", stdin_data: bytes)
    raise PublishError, "Invalid packaged plist: #{entry}" unless status.success?
    JSON.parse(json)
  end

  def inspect_ipa(path)
    ipa = File.realpath(path)
    _, _, status = Open3.capture3("unzip", "-tq", ipa)
    raise PublishError, "IPA ZIP integrity check failed" unless status.success?
    entries, _, status = Open3.capture3("unzip", "-Z1", ipa)
    raise PublishError, "Cannot list IPA contents" unless status.success?
    plists = entries.lines.map(&:strip).select { |entry| entry.match?(%r{\APayload/.*\.(?:app|appex)/Info\.plist\z}) }
    main = plists.select { |entry| entry.match?(%r{\APayload/[^/]+\.app/Info\.plist\z}) }
    raise PublishError, "Expected exactly one main app in IPA" unless main.length == 1
    app = plist(ipa, main.first)
    @bundle = app.fetch("CFBundleIdentifier")
    @version = app.fetch("CFBundleShortVersionString")
    @build = app.fetch("CFBundleVersion")
    raise PublishError, "Unexpected IPA bundle #{@bundle}" unless @bundle == "plainstride.outbound"
    raise PublishError, "Invalid IPA version/build" unless @version.match?(/\A\d+(?:\.\d+){0,2}\z/) && @build.match?(/\A\d+\z/)
    plists.each do |entry|
      data = plist(ipa, entry)
      unless data["CFBundleShortVersionString"] == @version && data["CFBundleVersion"] == @build
        raise PublishError, "Embedded bundle version mismatch: #{entry}"
      end
      modes = data.fetch("WKBackgroundModes", [])
      allowed = %w[workout-processing self-care mindfulness physical-therapy alarm]
      raise PublishError, "Unsupported WKBackgroundModes in #{entry}: #{(modes - allowed).join(', ')}" unless (modes - allowed).empty?
    end
    @sha256 = Digest::SHA256.file(ipa).hexdigest
    @md5 = Digest::MD5.file(ipa).hexdigest
    @size = File.size(ipa)
    log "IPA preflight passed: #{@version} (#{@build}), #{plists.length} app/extension bundles, #{@size} bytes"
    ipa
  end

  def matching_uploads
    api("GET", "/v1/apps/#{@app_id}/buildUploads", query: {
      "filter[cfBundleVersion]" => @build, "filter[cfBundleShortVersionString]" => @version, "limit" => 200
    }).fetch("data")
  end

  def check_state(upload)
    state = upload.dig("attributes", "state", "state")
    if state == "FAILED"
      details = upload.dig("attributes", "state", "errors").to_a.map { |error| [error["code"], error["description"] || error["message"]].compact.join(": ") }.join("; ")
      raise PublishError, "Apple rejected upload #{upload['id']}: #{details}; fix validation errors before retrying"
    end
    state
  end

  def prepare_upload
    uploads = matching_uploads
    raise PublishError, "Multiple matching Apple upload records; inspect them before proceeding" if uploads.length > 1
    if uploads.any?
      upload = uploads.first
      if @state["upload_id"] && @state["upload_id"] != upload["id"]
        raise PublishError, "Apple has a different upload record; refusing to overwrite another client's delivery"
      end
      # An interrupted POST may have succeeded before its response was saved.
      # The durable 'creating_upload' marker was saved before the request.
      unless @state["upload_id"] || @state["phase"] == "creating_upload"
        raise PublishError, "Existing upload #{upload['id']} belongs to another delivery. Stop its uploader and inspect/clear that exact record with testflight-upload-status.rb; do not rebuild."
      end
    else
      raise PublishError, "Saved Apple upload no longer exists; inspect the release state before starting a different upload" if @state["upload_id"]
      @state["phase"] = "creating_upload"
      save
      upload = api("POST", "/v1/buildUploads", payload: {data: {
        type: "buildUploads", attributes: {cfBundleShortVersionString: @version, cfBundleVersion: @build, platform: "IOS"},
        relationships: {app: {data: {type: "apps", id: @app_id}}}
      }}).fetch("data")
    end
    @state["upload_id"] = upload.fetch("id")
    @state["phase"] = "uploading"
    save
    log "Apple upload: #{upload['id']} (#{check_state(upload)})"
    upload
  end

  def prepare_file(upload)
    files = api("GET", "/v1/buildUploads/#{upload['id']}/buildUploadFiles", query: {"limit" => 200}).fetch("data")
    raise PublishError, "Upload contains analysis files from another client; refusing to mix delivery methods" if files.any? { |file| file.dig("attributes", "assetType") != "ASSET" }
    raise PublishError, "Multiple binary files in Apple upload" if files.length > 1
    if files.any?
      file = api("GET", "/v1/buildUploadFiles/#{files.first['id']}").fetch("data")
      if @state["file_id"] && @state["file_id"] != file["id"]
        raise PublishError, "Apple binary file differs from the checkpoint; refusing to mix deliveries"
      end
      raise PublishError, "Apple file size differs from preserved IPA" unless file.dig("attributes", "fileSize") == @size
    else
      file = api("POST", "/v1/buildUploadFiles", payload: {data: {
        type: "buildUploadFiles", attributes: {assetType: "ASSET", fileName: "Outbound.ipa", fileSize: @size, uti: "com.apple.ipa"},
        relationships: {buildUpload: {data: {type: "buildUploads", id: upload.fetch("id")}}}
      }}).fetch("data")
    end
    @state["file_id"] = file.fetch("id")
    save
    file
  end

  def upload_part(operation, index, total)
    uri = URI(operation.fetch("url"))
    raise PublishError, "Apple returned a non-HTTPS upload destination" unless uri.scheme == "https"
    offset = Integer(operation.fetch("offset"))
    length = Integer(operation.fetch("length"))
    attempts = 0
    begin
      attempts += 1
      # Apple's operation sizes bound this buffer. Sequential requests avoid
      # the native uploader's simultaneous analysis-file retry storm.
      body = File.binread(@ipa, length, offset)
      raise PublishError, "IPA changed or was truncated during upload" unless body.bytesize == length
      request = Net::HTTP.const_get(operation.fetch("method").capitalize).new(uri)
      operation.fetch("requestHeaders", []).each { |header| request[header.fetch("name")] = header.fetch("value") }
      request.body = body
      request.content_length = length
      # Never send the App Store Connect bearer token to object storage.
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 90, write_timeout: 90) do |http|
        http.max_retries = 0
        http.request(request)
      end
      unless response.is_a?(Net::HTTPSuccess)
        raise RetryableResponse, "HTTP #{response.code}" if TRANSIENT_HTTP.include?(response.code.to_i)
        raise PublishError, "Chunk #{index}/#{total}: HTTP #{response.code}; checkpoint preserved (upload URL omitted)"
      end
    rescue RetryableResponse, *NETWORK_ERRORS => error
      if attempts < 4
        context = error.is_a?(RetryableResponse) ? error.message : error.class.to_s
        log "Chunk #{index}/#{total}: #{context}; retry #{attempts}/3"
        sleep [2**attempts, 10].min
        retry
      end
      context = error.is_a?(RetryableResponse) ? error.message : error.class.to_s
      raise PublishError, "Chunk #{index}/#{total}: #{context}; checkpoint preserved, rerun the same command"
    end
  end

  def deliver(file)
    if file.dig("attributes", "assetDeliveryState", "state") == "FAILED"
      raise PublishError, "Apple rejected binary file #{file['id']}; inspect upload errors before retrying"
    end
    if file.dig("attributes", "assetDeliveryState", "state") == "COMPLETE"
      @state["phase"] = "processing"
      save
      log "Apple already has the complete binary file; no chunks repeated."
      return
    end
    operations = file.dig("attributes", "uploadOperations").to_a.sort_by { |operation| operation.fetch("offset") }
    cursor = 0
    keys = operations.map do |operation|
      offset, length = operation.values_at("offset", "length")
      raise PublishError, "Apple upload operations do not cover the IPA contiguously" unless offset == cursor && length.is_a?(Integer) && length.positive?
      cursor += length
      "#{offset}:#{length}:#{operation['partNumber']}"
    end
    raise PublishError, "Apple upload operation size differs from IPA" unless cursor == @size
    if @state["operation_keys"] && @state["operation_keys"] != keys
      raise PublishError, "Apple changed upload chunk boundaries; refusing to reuse an incompatible checkpoint"
    end
    @state["operation_keys"] = keys
    @state["completed_parts"] ||= []
    save
    operations.each_with_index do |operation, index|
      next if @state["completed_parts"].include?(keys[index])
      upload_part(operation, index + 1, operations.length)
      @state["completed_parts"] << keys[index]
      save
      log "Chunk #{index + 1}/#{operations.length} accepted (#{operation['offset'] + operation['length']}/#{@size} bytes)"
    end
    raise PublishError, "Preserved IPA changed before finalization" unless Digest::SHA256.file(@ipa).hexdigest == @sha256
    @state["phase"] = "finalizing"
    save
    api("PATCH", "/v1/buildUploadFiles/#{file['id']}", payload: {data: {
      type: "buildUploadFiles", id: file.fetch("id"), attributes: {uploaded: true, sourceFileChecksums: {file: {hash: @md5, algorithm: "MD5"}}}
    }})
    @state["phase"] = "processing"
    save
    log "Binary delivered; Apple processing is a separate stage. Resume public submission with --setup-only."
  end

  def run
    source = inspect_ipa(@options.fetch(:ipa))
    return if @options[:preflight_only]
    raise PublishError, "App Store Connect key is unavailable" unless File.readable?(@key_path)
    processes, _, status = Open3.capture3("ps", "-axo", "comm=")
    raise PublishError, "Cannot check for other upload clients" unless status.success?
    cli_running = system("pgrep", "-f", "java.*com.apple.transporter.launcher", out: File::NULL, err: File::NULL)
    if cli_running || processes.lines.any? { |line| line.strip.match?(%r{/(?:altool|Transporter)\z}) }
      raise PublishError, "Close Transporter and stop altool before starting the API uploader; never run delivery clients concurrently"
    end
    root = File.expand_path(ENV.fetch("ASC_RELEASE_ROOT", "~/Library/Application Support/Plainstride/Releases"))
    FileUtils.mkdir_p(root, mode: 0o700)
    File.open(File.join(root, ".upload.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
      raise PublishError, "Another repository uploader owns the release lock" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      directory = File.join(root, "#{@version}-#{@build}")
      FileUtils.mkdir_p(directory, mode: 0o700)
      @state_path = File.join(directory, "upload.json")
      @events_path = File.join(directory, "events.jsonl")
      @state = JSON.parse(File.read(@state_path)) if File.exist?(@state_path)
      identity = {"bundle_id" => @bundle, "version" => @version, "build" => @build, "sha256" => @sha256, "size" => @size}
      identity.each { |key, value| raise PublishError, "Release checkpoint #{key} differs; do not change a prepared build" if @state.key?(key) && @state[key] != value }
      @state.merge!(identity)
      @state["source_commit"] ||= ENV["ASC_SOURCE_COMMIT"] unless ENV["ASC_SOURCE_COMMIT"].to_s.empty?
      @state["archive_path"] ||= ENV["ASC_ARCHIVE_PATH"] unless ENV["ASC_ARCHIVE_PATH"].to_s.empty?
      @ipa = File.join(directory, "Outbound.ipa")
      FileUtils.cp(source, @ipa) unless File.exist?(@ipa)
      raise PublishError, "Preserved IPA checksum mismatch" unless Digest::SHA256.file(@ipa).hexdigest == @sha256
      @state["ipa_path"] = @ipa
      save
      log "Durable release: #{directory}"
      apps = api("GET", "/v1/apps", query: {"filter[bundleId]" => @bundle, "limit" => 2}).fetch("data")
      raise PublishError, "Expected one App Store Connect app" unless apps.length == 1
      @app_id = apps.first.fetch("id")
      builds = api("GET", "/v1/builds", query: {"filter[app]" => @app_id, "filter[version]" => @build, "filter[preReleaseVersion.version]" => @version, "limit" => 2}).fetch("data")
      unless builds.empty?
        raise PublishError, "Apple has multiple matching builds" unless builds.length == 1
        processing = builds.first.dig("attributes", "processingState")
        raise PublishError, "Apple build is #{processing}; inspect validation errors instead of re-uploading" if %w[FAILED INVALID].include?(processing)
        @state["phase"] = "accepted"
        @state["build_id"] = builds.first.fetch("id")
        save
        log "Apple already has this build; no upload repeated. Continue with --setup-only."
        return
      end
      upload = prepare_upload
      if %w[PROCESSING COMPLETE].include?(check_state(upload))
        @state["phase"] = "processing"
        save
        log "Apple already received the binary; no chunks repeated. Continue with --setup-only."
        return
      end
      deliver(prepare_file(upload))
    end
  rescue PublishError => error
    if @state_path
      @state["last_error"] = error.message
      save
      log "Delivery stopped: #{error.message}"
    end
    warn "error: #{error.message}"
    warn "Release state preserved: #{@state_path}" if @state_path
    exit 1
  rescue Interrupt, SignalException
    log "Delivery interrupted; completed chunks and the signed IPA are preserved for the same command"
    exit 130
  rescue StandardError => error
    warn "error: Publish operation failed in #{@state['phase'] || 'preflight'}: #{error.class} at #{error.backtrace.first}"
    warn "Checkpoint is preserved; inspect this failure before rerunning."
    exit 1
  end
end

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/asc-upload-ipa.rb --ipa PATH [--preflight-only]"
  parser.on("--ipa PATH", "Signed IPA to preserve and deliver (resumes the same identity/checkpoint)") { |value| options[:ipa] = value }
  parser.on("--preflight-only", "Check ZIP, bundle versions, and Watch background modes without network or writes") { options[:preflight_only] = true }
end.parse!
abort "--ipa is required" unless options[:ipa] && ARGV.empty?
ASCUpload.new(options).run
