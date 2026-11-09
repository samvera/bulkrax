# frozen_string_literal: true

module Bulkrax
  class DownloadCloudFileJob < ApplicationJob
    queue_as Bulkrax.config.ingest_queue_name

    # Retrieve a cloud file and write it to the importer's workspace.
    #
    # `importer_id:` and `relative_filename:` are required keywords: the
    # destination is always recomputed here, confined to this importer's
    # own workspace, rather than trusted from a serialized job argument.
    # `target_file` is a deprecated positional placeholder, kept only so
    # that a pre-upgrade call shape (`file`, `target_file`) still binds
    # without Ruby raising its own ArgumentError — it is never read, even
    # when supplied alongside otherwise-valid keywords, so it can't be
    # used to redirect the destination. A call made this way is missing
    # the required keywords, so it raises below rather than running.
    #
    # Note: if using the file system provider, the mounted directory in
    #   browse_everything MUST be shared by web and worker servers
    def perform(file, target_file = nil, importer_id: nil, relative_filename: nil)
      raise Bulkrax::UnsafePathError, I18n.t('bulkrax.importer.browse_everything.errors.missing_destination_context') if importer_id.blank? || relative_filename.blank?

      # `file` and `relative_filename` are independent arguments and may
      # not agree (a tampered or replayed job call could supply either
      # one separately) — check the raw file_name directly rather than
      # assuming it was already validated by whatever enqueued this job.
      Bulkrax::SafePath.reject_unsafe_entry!(file['file_name'])

      importer = Bulkrax::Importer.find(importer_id)
      target_file = Bulkrax::SafePath.confine!(importer.parser.path_for_import, relative_filename, require_file: true)

      # Re-validate the source here too: this job may run on a different
      # process/host than the one that enqueued it, and could be invoked
      # directly with a tampered or stale `file` argument.
      Bulkrax::CloudSourceValidator.validate!(file)

      download(file, target_file)
      Rails.logger.info "Bulkrax: cloud file download complete for #{file['file_name']}"
    end

    private

    # Downloads through a temp file in the *same* directory as
    # `target_file` (so the final move is same-filesystem and atomic),
    # named with a random suffix rather than anything derived from
    # caller-controlled input, and removed on any failure. This means a
    # failed or non-success download can never truncate or corrupt an
    # already-good destination file from a previous successful import.
    def download(file, target_file)
      temp_file = "#{target_file}.#{SecureRandom.hex(8)}.part"
      uri = Addressable::URI.parse(file['url'].to_s)
      if uri.scheme == 'file'
        download_file_source(uri, temp_file)
      else
        download_http_source(file, URI.parse(file['url'].to_s), temp_file)
      end
      FileUtils.mv(temp_file, target_file)
    ensure
      FileUtils.rm_f(temp_file) if temp_file && File.exist?(temp_file)
    end

    # The source was already confined to the configured filesystem
    # provider's root by {Bulkrax::CloudSourceValidator}.
    def download_file_source(uri, temp_file)
      source_path = URI::DEFAULT_PARSER.unescape(uri.path.to_s)
      IO.copy_stream(source_path, temp_file)
    end

    # Resolved, IP-pinned, redirect-free, and streamed straight to disk in
    # bounded-size chunks — rather than handing the URL back to a transport
    # (browse-everything's Retriever) that re-resolves the hostname with no
    # SSRF protection at all. This is a *separate* connection from the one
    # {Bulkrax::CloudSourceValidator}'s HEAD check made; each independently
    # applies the same validation at its own connection time, so there is
    # no single "pinned connection" shared between validation and download.
    #
    # ssrf_filter 1.0.8's public `get`/`head` API has no response-streaming
    # hook: `fetch_once` calls `Net::HTTP#request` with no block, which
    # reads the entire response body into memory before returning; the
    # block `get`/`head` accept is for customizing the *outgoing* request,
    # not consuming the response. So we can't use `SsrfFilter.get` here
    # without buffering the whole remote file in memory first.
    #
    # Reuse ssrf_filter's resolver and IP policy, then pin the validated
    # address with Net::HTTP#ipaddr=. Keeping the original hostname on
    # the HTTP connection preserves native TLS SNI and certificate
    # verification without relying on ssrf_filter's TLS monkeypatches.
    def download_http_source(file, uri, temp_file)
      headers = Bulkrax::CloudSourceValidator.request_headers(file)
      stream_download(uri, headers) { |response| handle_response(file, response, temp_file) }
    rescue SsrfFilter::Error
      # The validator's own HEAD check already ran, but DNS can change
      # between that check and this GET — same rationale as
      # Bulkrax::CloudSourceValidator#validate_http_scheme!, and the same
      # static, class-agnostic message for the same reason.
      raise Bulkrax::UnsafeCloudSourceError, 'blocked unsafe remote source'
    end

    def handle_response(file, response, temp_file)
      unless response.is_a?(Net::HTTPSuccess)
        # Static on purpose — this becomes the importer's status message,
        # not just an ops log; see Bulkrax::CloudSourceValidator for why
        # status codes/response details aren't echoed into it. The status
        # code itself is logged (not attacker-controlled, not a credential).
        Rails.logger.error("Bulkrax: cloud file download failed for #{file['file_name']} with status #{response.code}")
        raise Bulkrax::UnsafeCloudSourceError, 'download failed: non-success response'
      end

      File.open(temp_file, 'wb') { |io| response.read_body { |chunk| io.write(chunk) } }
    end

    # Resolves `uri`'s host, rejects it unless it has at least one public
    # IP (reusing ssrf_filter's own resolver/blacklist — see above), and
    # connects directly to that IP: with the environment proxy explicitly
    # disabled (`Net::HTTP.new`'s `p_addr` defaults to `:ENV`, which would
    # otherwise route through `http_proxy`/`https_proxy` and hand the
    # pinned connection to a third party), and with the real hostname sent
    # as the `Host` header and used for TLS SNI/certificate verification
    # instead of the IP. Yields the live `Net::HTTPResponse` to the block
    # *before* its body is read, so the caller can stream it.
    def stream_download(uri, headers)
      raise SsrfFilter::InvalidUriScheme, "URI scheme '#{uri.scheme}' not in whitelist" unless
        SsrfFilter::DEFAULT_SCHEME_WHITELIST.include?(uri.scheme)

      hostname = uri.hostname
      ip_addresses = SsrfFilter::DEFAULT_RESOLVER.call(hostname)
      raise SsrfFilter::UnresolvedHostname, "Could not resolve hostname '#{hostname}'" if ip_addresses.empty?

      public_addresses = ip_addresses.reject { |ip| unsafe_ip_address?(ip) }
      raise SsrfFilter::PrivateIPAddress, "Hostname '#{hostname}' has no public ip addresses" if public_addresses.empty?

      request = Net::HTTP::Get.new(uri)
      request['host'] = host_header(hostname, uri)
      headers.each { |key, value| request[key] = value }

      http = Net::HTTP.new(hostname, uri.port, nil)
      http.ipaddr = public_addresses.sample.to_s
      http.use_ssl = (uri.scheme == 'https')
      http.start { |connection| connection.request(request) { |response| yield response } }
    end

    # Mirrors `SsrfFilter.unsafe_ip_address?`, but against its public
    # `IPV4_BLACKLIST`/`IPV6_BLACKLIST` constants directly rather than
    # calling that private method — we only ever check single resolved
    # addresses here (never a CIDR range), so the masked-range guard it
    # also carries doesn't apply.
    def unsafe_ip_address?(ip_address)
      return SsrfFilter::IPV4_BLACKLIST.any? { |range| range.include?(ip_address) } if ip_address.ipv4?
      return SsrfFilter::IPV6_BLACKLIST.any? { |range| range.include?(ip_address) } if ip_address.ipv6?

      true
    end

    # Matches `SsrfFilter.host_header`: the `Host` header should carry the
    # real hostname (not the pinned IP we actually connect to), with the
    # port suffixed only when it isn't the scheme's default.
    def host_header(hostname, uri)
      if (uri.port == 80 && uri.scheme == 'http') || (uri.port == 443 && uri.scheme == 'https')
        hostname
      else
        "#{hostname}:#{uri.port}"
      end
    end
  end
end
