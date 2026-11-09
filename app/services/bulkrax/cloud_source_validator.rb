# frozen_string_literal: true

module Bulkrax
  # Validates a cloud-file source (the Hash a user selected via
  # browse-everything, or supplied directly in importer params) before
  # Bulkrax downloads it. Destination confinement (see {Bulkrax::SafePath})
  # stops a malicious filename from writing outside the importer's
  # workspace; this validator stops a malicious `url` from reading a local
  # file outside the configured filesystem-provider root, or from reaching
  # a private/internal network over HTTP(S) (SSRF).
  #
  # Called twice by design: once before enqueueing, so an obviously unsafe
  # batch never reaches a job queue, and again inside the download job,
  # so a legacy or tampered job argument can't bypass validation.
  class CloudSourceValidator
    LOCAL_FILE_HOSTS = ['', 'localhost'].freeze

    # Lightweight preflight for a single cloud-file selection: checks the
    # raw file name and the source's safety, without resolving anything
    # against an importer's workspace. Shared by CsvParser#plan_cloud_file,
    # BagitParser#retrieve_cloud_files, and ImportersController's pre-save
    # check, so a selection is judged unsafe the same way whether or not an
    # importer has been persisted yet.
    #
    # @param file [Hash] a single cloud-file spec with at least `url` and `file_name` keys
    # @raise [Bulkrax::UnsafePathError] if the raw file name is unsafe
    # @raise [Bulkrax::UnsafeCloudSourceError] if the source isn't safe to download
    # @return [true]
    def self.preflight!(file)
      name = file['file_name'] || file[:file_name]
      raise Bulkrax::UnsafePathError, 'cloud file name must not be blank' if name.blank?
      Bulkrax::SafePath.reject_unsafe_entry!(name)
      validate!(file)
    end

    # @param file [Hash] a single cloud-file spec with at least a `url` key
    # @raise [Bulkrax::UnsafeCloudSourceError] if the source isn't safe to download
    # @return [true]
    def self.validate!(file)
      url = file['url'] || file[:url]
      raise Bulkrax::UnsafeCloudSourceError, 'the cloud file is missing a url' if url.blank?

      uri = parse_uri(url)
      case uri.scheme
      when 'file'
        validate_file_scheme!(uri)
      when 'http', 'https'
        validate_http_scheme!(uri, file)
      else
        raise Bulkrax::UnsafeCloudSourceError, 'unsupported source scheme'
      end
      true
    end

    def self.parse_uri(url)
      Addressable::URI.parse(url.to_s)
    rescue Addressable::URI::InvalidURIError
      raise Bulkrax::UnsafeCloudSourceError, 'the cloud file url is malformed'
    end
    private_class_method :parse_uri

    def self.validate_file_scheme!(uri)
      raise Bulkrax::UnsafeCloudSourceError, 'a file: source must not specify a remote host' unless LOCAL_FILE_HOSTS.include?(uri.host.to_s)

      home = file_system_home
      raise Bulkrax::UnsafeCloudSourceError, 'the filesystem provider is not configured' if home.blank?

      decoded_path = URI::DEFAULT_PARSER.unescape(uri.path.to_s)
      Bulkrax::SafePath.confine!(home, decoded_path, require_file: true, allow_absolute: true)
    rescue Bulkrax::UnsafePathError => e
      raise Bulkrax::UnsafeCloudSourceError, e.message
    end
    private_class_method :validate_file_scheme!

    # Enforced at connection time, not by a DNS preflight: SsrfFilter
    # resolves the hostname, rejects private/loopback/link-local/metadata
    # addresses, and then connects directly to the validated IP (with TLS
    # verified against the original hostname), closing the gap a
    # resolve-then-connect check would leave open to DNS rebinding.
    # Redirects are disabled outright (rather than re-validated per hop)
    # so a header carrying provider credentials is never resent to a
    # different host.
    def self.validate_http_scheme!(uri, file)
      raise Bulkrax::UnsafeCloudSourceError, 'no remote cloud provider is configured' unless remote_provider_configured?
      raise Bulkrax::UnsafeCloudSourceError, 'the cloud file url must include a host' if uri.host.blank?
      raise Bulkrax::UnsafeCloudSourceError, 'the cloud file url must not include credentials' if uri.userinfo.present?

      SsrfFilter.head(uri.to_s, headers: request_headers(file), max_redirects: 0)
    rescue SsrfFilter::Error, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      # Static and class-agnostic on purpose: SsrfFilter's own exception
      # message can include the resolved IP or hostname it rejected, and
      # this error is shown to the importing user / written to the
      # importer's status, not just an ops log.
      raise Bulkrax::UnsafeCloudSourceError, 'blocked unsafe remote source'
    end
    private_class_method :validate_http_scheme!

    # Merges the caller-supplied headers (used for provider auth) but
    # strips any transport-control header a malicious selection could use
    # to smuggle a different Host past SsrfFilter's own Host header.
    def self.request_headers(file)
      headers = {}
      headers.merge!(file['headers'] || file[:headers] || {})
      headers.merge!(file['auth_header'] || file[:auth_header] || {})
      headers.reject { |key, _| key.to_s.casecmp('host').zero? }
    end

    def self.file_system_home
      config = provider_config('file_system')
      config && (config['home'] || config[:home])
    end

    def self.remote_provider_configured?
      BrowseEverything.config.any? { |key, value| key.to_s != 'file_system' && value.present? }
    end

    def self.provider_config(name)
      config = BrowseEverything.config
      config[name] || config[name.to_sym]
    end
    private_class_method :provider_config
  end
end
