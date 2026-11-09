# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe DownloadCloudFileJob, type: :job do
    subject(:job) { described_class.new }

    let(:importer) { FactoryBot.create(:bulkrax_importer) }
    let(:workspace) { importer.parser.path_for_import }

    after { FileUtils.rm_rf(workspace) }

    def stub_browse_everything_config(config)
      allow(BrowseEverything).to receive(:config).and_return(config.with_indifferent_access)
    end

    describe '#perform' do
      context 'with legacy (pre-upgrade, two-positional-argument) job arguments' do
        it 'raises a clear error instead of trusting the old absolute target path' do
          legacy_absolute_path = File.join(workspace, 'files', 'a.pdf')

          expect { job.perform({ 'url' => 'http://example.com/a.pdf' }, legacy_absolute_path) }
            .to raise_error(Bulkrax::UnsafePathError, /missing required destination information/)
        end
      end

      context 'with importer_id missing' do
        it 'raises before any lookup, path creation, network request, or write' do
          expect(Bulkrax::Importer).not_to receive(:find)
          expect(SsrfFilter).not_to receive(:get)

          expect do
            job.perform({ 'url' => 'http://example.com/a.pdf' }, relative_filename: 'files/a.pdf')
          end.to raise_error(Bulkrax::UnsafePathError, /missing required destination information/)
        end
      end

      context 'with importer_id blank' do
        it 'raises before any lookup, path creation, network request, or write' do
          expect(Bulkrax::Importer).not_to receive(:find)
          expect(SsrfFilter).not_to receive(:get)

          expect do
            job.perform({ 'url' => 'http://example.com/a.pdf' }, importer_id: '', relative_filename: 'files/a.pdf')
          end.to raise_error(Bulkrax::UnsafePathError, /missing required destination information/)
        end
      end

      context 'with relative_filename missing' do
        it 'raises before any lookup, path creation, network request, or write' do
          expect(Bulkrax::Importer).not_to receive(:find)
          expect(SsrfFilter).not_to receive(:get)

          expect do
            job.perform({ 'url' => 'http://example.com/a.pdf' }, importer_id: importer.id)
          end.to raise_error(Bulkrax::UnsafePathError, /missing required destination information/)
        end
      end

      context 'with relative_filename blank' do
        it 'raises before any lookup, path creation, network request, or write' do
          expect(Bulkrax::Importer).not_to receive(:find)
          expect(SsrfFilter).not_to receive(:get)

          expect do
            job.perform({ 'url' => 'http://example.com/a.pdf' }, importer_id: importer.id, relative_filename: '')
          end.to raise_error(Bulkrax::UnsafePathError, /missing required destination information/)
        end
      end

      context 'with both importer_id and relative_filename missing' do
        it 'raises before any lookup, path creation, network request, or write' do
          expect(Bulkrax::Importer).not_to receive(:find)
          expect(SsrfFilter).not_to receive(:get)

          expect do
            job.perform({ 'url' => 'http://example.com/a.pdf' })
          end.to raise_error(Bulkrax::UnsafePathError, /missing required destination information/)
        end
      end

      # The deprecated positional `target_file` placeholder must never
      # influence the actual destination, even when supplied alongside
      # otherwise-valid keywords — the destination is always recomputed
      # from the loaded importer's own workspace and the validated
      # `relative_filename`.
      context 'with an outside-root target_file positional argument alongside valid keywords' do
        let(:provider_root) { File.realpath(Dir.mktmpdir) }
        let(:source_path) { File.join(provider_root, 'source.pdf') }

        before do
          stub_browse_everything_config(file_system: { home: provider_root })
          File.write(source_path, 'safe-bytes')
        end

        after { FileUtils.rm_rf(provider_root) }

        it 'ignores the positional target_file and writes only to the confined destination' do
          outside_dir = Dir.mktmpdir
          malicious_target = File.join(outside_dir, 'hijacked.pdf')
          target = File.join(workspace, 'files', 'a.pdf')
          FileUtils.mkdir_p(File.dirname(target))

          job.perform(
            { 'url' => "file://#{source_path}", 'file_name' => 'a.pdf' },
            malicious_target,
            importer_id: importer.id,
            relative_filename: 'files/a.pdf'
          )

          expect(File.read(target)).to eq('safe-bytes')
          expect(File).not_to exist(malicious_target)
        ensure
          FileUtils.rm_rf(outside_dir)
        end
      end

      context 'with a relative_filename that escapes the importer workspace' do
        before { stub_browse_everything_config({}) }

        it 'raises before any download is attempted' do
          expect(SsrfFilter).not_to receive(:get)

          expect do
            job.perform({ 'url' => 'file:///etc/passwd' }, importer_id: importer.id, relative_filename: '../../etc/passwd')
          end.to raise_error(Bulkrax::UnsafePathError)
        end
      end

      # The job trusts `relative_filename` as its own, independent
      # argument — it doesn't re-derive it from `file['file_name']`. An
      # attacker able to invoke the job directly (a tampered or replayed
      # job argument) could pass a relative_filename containing `..`
      # that still resolves inside the workspace; that must be rejected
      # outright rather than "resolved and found to be fine".
      context 'with a relative_filename containing a `..` segment that still resolves inside the workspace' do
        before { stub_browse_everything_config({}) }

        it 'raises before any download is attempted' do
          expect(SsrfFilter).not_to receive(:get)

          expect do
            job.perform({ 'url' => 'file:///etc/passwd' }, importer_id: importer.id, relative_filename: 'files/../a.pdf')
          end.to raise_error(Bulkrax::UnsafePathError)
        end
      end

      context 'with a relative_filename that is an absolute path' do
        before { stub_browse_everything_config({}) }

        it 'raises before any download is attempted' do
          expect(SsrfFilter).not_to receive(:get)

          expect do
            job.perform({ 'url' => 'file:///etc/passwd' }, importer_id: importer.id, relative_filename: '/etc/passwd')
          end.to raise_error(Bulkrax::UnsafePathError)
        end
      end

      # `file` and `relative_filename` are two independent job arguments;
      # the job must not assume they agree with each other, since either
      # could come from a tampered or replayed job call.
      context "with a file_name that disagrees with (and is unsafe relative to) relative_filename" do
        before { stub_browse_everything_config({}) }

        it 'raises before any download is attempted' do
          expect(SsrfFilter).not_to receive(:get)

          expect do
            job.perform({ 'url' => 'file:///etc/passwd', 'file_name' => '../a.pdf' }, importer_id: importer.id, relative_filename: 'files/a.pdf')
          end.to raise_error(Bulkrax::UnsafePathError)
        end
      end

      context 'with an unsafe source' do
        before { stub_browse_everything_config({}) }

        it 'raises before writing the destination file' do
          target = File.join(workspace, 'files', 'a.pdf')

          expect do
            job.perform({ 'url' => 'http://169.254.169.254/latest/meta-data/', 'file_name' => 'a.pdf' }, importer_id: importer.id, relative_filename: 'files/a.pdf')
          end.to raise_error(Bulkrax::UnsafeCloudSourceError)

          expect(File).not_to exist(target)
        end
      end

      context 'with a file: source inside the configured filesystem provider root' do
        let(:provider_root) { File.realpath(Dir.mktmpdir) }
        let(:source_path) { File.join(provider_root, 'source.pdf') }

        before do
          stub_browse_everything_config(file_system: { home: provider_root })
          File.write(source_path, 'source-bytes')
        end

        after { FileUtils.rm_rf(provider_root) }

        it 'copies the file into the importer workspace' do
          target = File.join(workspace, 'files', 'a.pdf')
          FileUtils.mkdir_p(File.dirname(target))

          job.perform({ 'url' => "file://#{source_path}", 'file_name' => 'a.pdf' }, importer_id: importer.id, relative_filename: 'files/a.pdf')

          expect(File.read(target)).to eq('source-bytes')
        end
      end

      # Unit-level coverage of the two seams `download_http_source` is
      # split into: {#handle_response} (turns a live response into bytes
      # on disk) and {#stream_download} (resolves, pins, and connects).
      # Testing `handle_response` directly — rather than only through a
      # full `SsrfFilter.get`-style double with a pre-built `.body` — is
      # what lets these specs prove the response is consumed via
      # `#read_body` in chunks and never aggregated into memory: the old
      # implementation (`File.binwrite(temp_file, response.body)`) calls
      # `.body`, which the first example below forbids outright.
      context 'with an http(s) source' do
        let(:target) { File.join(workspace, 'files', 'a.pdf') }
        let(:file) { { 'file_name' => 'a.pdf' } }

        before { FileUtils.mkdir_p(File.dirname(target)) }

        it 'writes each chunk as it is read, never aggregating the full response body' do
          chunks = %w[chunk-one chunk-two chunk-three]
          response = instance_double(Net::HTTPOK)
          allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          allow(response).to receive(:body).and_raise('must stream via #read_body, not #body')
          allow(response).to receive(:read_body) { |&blk| chunks.each { |chunk| blk.call(chunk) } }

          job.send(:handle_response, file, response, target)

          expect(File.read(target)).to eq(chunks.join)
        end

        it 'raises a static, sanitized message and writes nothing when the response is not a success' do
          response = instance_double(Net::HTTPNotFound, code: '404')
          allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)

          expect { job.send(:handle_response, file, response, target) }
            .to raise_error(Bulkrax::UnsafeCloudSourceError, /non-success/)

          expect(File).not_to exist(target)
        end
      end

      # Same technique as the equivalent block in cloud_source_validator_spec.rb:
      # DNS resolution is stubbed to a real IP (the same injection point
      # `SsrfFilter::DEFAULT_RESOLVER` uses, and that {#stream_download}
      # reuses directly) so WebMock can intercept the resulting real
      # Net::HTTP connection — resolve/blacklist/redirect/header logic all
      # runs unmocked, for both the validator's HEAD and this job's GET.
      context 'with an http(s) source, against real (unstubbed) DNS resolution' do
        let(:target) { File.join(workspace, 'files', 'a.pdf') }
        let(:fake_public_ip) { '8.8.8.8' }
        let(:host) { 'cloud-provider.example.test' }
        # Support URI-rewriting and connection-pinning ssrf_filter releases.
        let(:head_url) { %r{\Ahttps?://(?:#{Regexp.escape(host)}|#{Regexp.escape(fake_public_ip)})/a\.pdf\z} }

        before do
          stub_browse_everything_config(box: { client_id: 'abc' })
          allow(Resolv).to receive(:getaddresses).with(host).and_return([fake_public_ip])
          FileUtils.mkdir_p(File.dirname(target))
        end

        it 'downloads real bytes end-to-end through the SSRF-safe transport' do
          stub_request(:head, head_url).to_return(status: 200)
          stub_request(:get, "http://#{host}/a.pdf").to_return(status: 200, body: 'real-remote-bytes')

          job.perform({ 'url' => "http://#{host}/a.pdf", 'file_name' => 'a.pdf' }, importer_id: importer.id, relative_filename: 'files/a.pdf')

          expect(File.read(target)).to eq('real-remote-bytes')
        end

        it 'never completes the download at all if the real GET is answered with a redirect' do
          stub_request(:head, head_url).to_return(status: 200)
          stub_request(:get, "http://#{host}/a.pdf")
            .to_return(status: 302, headers: { 'Location' => 'http://attacker.example/steal' })

          expect do
            job.perform({ 'url' => "http://#{host}/a.pdf", 'file_name' => 'a.pdf' }, importer_id: importer.id, relative_filename: 'files/a.pdf')
          end.to raise_error(Bulkrax::UnsafeCloudSourceError)

          expect(File).not_to exist(target)
          expect(Dir.children(File.dirname(target))).to be_empty
        end

        it 'leaves no temp/partial file behind and does not truncate a pre-existing destination on failure' do
          File.write(target, 'previously-good-bytes')
          stub_request(:head, head_url).to_return(status: 200)
          stub_request(:get, "http://#{host}/a.pdf").to_return(status: 404, body: 'nope')

          expect do
            job.perform({ 'url' => "http://#{host}/a.pdf", 'file_name' => 'a.pdf' }, importer_id: importer.id, relative_filename: 'files/a.pdf')
          end.to raise_error(Bulkrax::UnsafeCloudSourceError)

          expect(File.read(target)).to eq('previously-good-bytes')
          expect(Dir.children(File.dirname(target))).to eq(['a.pdf'])
        end

        it 'connects to the pinned IP with the environment proxy disabled and the real hostname as the Host header' do
          allow(Net::HTTP).to receive(:new).and_call_original
          stub_request(:head, head_url).to_return(status: 200)
          stub_request(:get, "https://#{host}/a.pdf")
            .with(headers: { 'Host' => host }).to_return(status: 200, body: 'real-remote-bytes')

          job.perform({ 'url' => "https://#{host}/a.pdf", 'file_name' => 'a.pdf' }, importer_id: importer.id, relative_filename: 'files/a.pdf')

          expect(Net::HTTP).to have_received(:new).with(host, 443, nil)
          expect(File.read(target)).to eq('real-remote-bytes')
        end

        it 'retains the TLS hostname while pinning the connection with the public Net::HTTP ipaddr API' do
          observed_connection = nil
          allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
            observed_connection = original.call(*args)
          end
          stub_request(:head, head_url).to_return(status: 200)
          stub_request(:get, "https://#{host}/a.pdf").to_return(status: 200, body: 'bytes')

          job.perform({ 'url' => "https://#{host}/a.pdf", 'file_name' => 'a.pdf' }, importer_id: importer.id, relative_filename: 'files/a.pdf')

          expect(observed_connection.address).to eq(host)
          expect(observed_connection.ipaddr).to eq(fake_public_ip)
          expect(observed_connection.verify_mode).not_to eq(OpenSSL::SSL::VERIFY_NONE)
        end
      end

      # These resolve to addresses SsrfFilter's own IPV4_BLACKLIST /
      # IPV6_BLACKLIST (reused directly by {#unsafe_ip_address?}) reject —
      # the same DNS-rebinding-shaped gap Bulkrax::CloudSourceValidator's
      # own HEAD check closes by validating at connection time rather than
      # a separate preflight.
      context 'with an http(s) source that resolves to an unsafe address' do
        let(:target) { File.join(workspace, 'files', 'a.pdf') }

        before do
          stub_browse_everything_config(box: { client_id: 'abc' })
          allow(SsrfFilter).to receive(:head)
          FileUtils.mkdir_p(File.dirname(target))
        end

        [['a private address', '10.0.0.5'], ['an IPv4-mapped IPv6 loopback address', '::ffff:127.0.0.1']].each do |label, ip|
          it "blocks the download before ever opening a connection, for #{label}" do
            allow(Resolv).to receive(:getaddresses).and_return([ip])
            expect(Net::HTTP).not_to receive(:new)

            expect do
              job.perform({ 'url' => 'https://internal.example.test/a.pdf', 'file_name' => 'a.pdf' }, importer_id: importer.id, relative_filename: 'files/a.pdf')
            end.to raise_error(Bulkrax::UnsafeCloudSourceError)
          end
        end
      end

      # WebMock's Net::HTTP stub can't interrupt a response mid-`#read_body`
      # the way a dropped real connection would, so this exercises that
      # failure mode by controlling the Net::HTTP connection directly: the
      # point is to prove {#download}'s temp-file cleanup still runs even
      # though bytes are now written incrementally as they arrive, rather
      # than in the single all-or-nothing `File.binwrite` the old
      # implementation used.
      context 'with a connection that fails partway through a streamed body' do
        let(:target) { File.join(workspace, 'files', 'a.pdf') }
        let(:http) { instance_double(Net::HTTP) }
        let(:response) { instance_double(Net::HTTPOK) }

        before do
          stub_browse_everything_config(box: { client_id: 'abc' })
          allow(SsrfFilter).to receive(:head)
          allow(Resolv).to receive(:getaddresses).and_return(['93.184.216.34'])
          allow(Net::HTTP).to receive(:new).and_return(http)
          allow(http).to receive(:use_ssl=)
          allow(http).to receive(:ipaddr=)
          allow(http).to receive(:start) { |&blk| blk.call(http) }
          allow(http).to receive(:request) { |_req, &blk| blk.call(response) }
          allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          allow(response).to receive(:read_body) do |&blk|
            blk.call('partial-bytes')
            raise IOError, 'connection reset'
          end
          FileUtils.mkdir_p(File.dirname(target))
        end

        it 'removes the partial temp file and leaves no trace at the destination' do
          expect do
            job.perform({ 'url' => 'https://example.com/a.pdf', 'file_name' => 'a.pdf' }, importer_id: importer.id, relative_filename: 'files/a.pdf')
          end.to raise_error(IOError)

          expect(File).not_to exist(target)
          expect(Dir.children(File.dirname(target))).to be_empty
        end

        it 'does not truncate a pre-existing destination file' do
          File.write(target, 'previously-good-bytes')

          expect do
            job.perform({ 'url' => 'https://example.com/a.pdf', 'file_name' => 'a.pdf' }, importer_id: importer.id, relative_filename: 'files/a.pdf')
          end.to raise_error(IOError)

          expect(File.read(target)).to eq('previously-good-bytes')
        end
      end
    end

    describe 'ActiveJob keyword argument serialization' do
      include ActiveJob::TestHelper

      let(:target) { File.join(workspace, 'files', 'a.pdf') }
      let(:provider_root) { File.realpath(Dir.mktmpdir) }
      let(:source_path) { File.join(provider_root, 'source.pdf') }

      before do
        stub_browse_everything_config(file_system: { home: provider_root })
        FileUtils.mkdir_p(File.dirname(target))
        File.write(source_path, 'serialized-bytes')
      end

      after { FileUtils.rm_rf(provider_root) }

      it 'round-trips importer_id: and relative_filename: through enqueue, serialize, deserialize, and perform' do
        perform_enqueued_jobs do
          Bulkrax::DownloadCloudFileJob.perform_later(
            { 'url' => "file://#{source_path}", 'file_name' => 'a.pdf' },
            importer_id: importer.id,
            relative_filename: 'files/a.pdf'
          )
        end

        expect(File.read(target)).to eq('serialized-bytes')
      end

      # ActiveJob's test adapter runs the deserialized job through the
      # Rails executor/reloader, which re-raises job errors wrapped in
      # Minitest::UnexpectedError — so the underlying error surfaces as
      # `#cause` here rather than as the raised exception's own class.
      it 'raises Bulkrax::UnsafePathError on perform when a job enqueued without the keywords is executed' do
        expect do
          perform_enqueued_jobs do
            Bulkrax::DownloadCloudFileJob.perform_later({ 'url' => 'http://example.com/a.pdf' })
          end
        end.to raise_error { |error| expect([error, error.cause]).to include(an_instance_of(Bulkrax::UnsafePathError)) }
      end
    end
  end
end
