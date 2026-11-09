# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::CloudSourceValidator do
  def stub_browse_everything_config(config)
    allow(BrowseEverything).to receive(:config).and_return(config.with_indifferent_access)
  end

  describe '.preflight!' do
    [nil, '', '   '].each do |name|
      it "rejects blank file name #{name.inspect} before source validation" do
        expect(described_class).not_to receive(:validate!)
        expect { described_class.preflight!('url' => 'https://example.com/a.pdf', 'file_name' => name) }
          .to raise_error(Bulkrax::UnsafePathError)
      end
    end

    it 'rejects an unsafe raw file name before validating the source' do
      expect { described_class.preflight!('url' => 'https://example.com/a.pdf', 'file_name' => '../../etc/passwd') }
        .to raise_error(Bulkrax::UnsafePathError)
    end

    it 'validates the source once the file name is safe' do
      stub_browse_everything_config({})

      expect { described_class.preflight!('url' => 'https://example.com/a.pdf', 'file_name' => 'a.pdf') }
        .to raise_error(Bulkrax::UnsafeCloudSourceError, /no remote cloud provider/)
    end

    it 'returns true for a safe file name and source, without resolving any importer workspace' do
      stub_browse_everything_config(box: { client_id: 'abc' })
      allow(SsrfFilter).to receive(:head)

      expect(described_class.preflight!('url' => 'https://example.com/a.pdf', 'file_name' => 'a.pdf')).to be true
    end
  end

  describe '.validate!' do
    context 'with a missing url' do
      it 'raises' do
        expect { described_class.validate!({}) }
          .to raise_error(Bulkrax::UnsafeCloudSourceError, /missing a url/)
      end
    end

    context 'with a malformed url' do
      it 'raises' do
        expect { described_class.validate!('url' => "http:// bad") }
          .to raise_error(Bulkrax::UnsafeCloudSourceError, /malformed/)
      end
    end

    context 'with an unsupported scheme' do
      before { stub_browse_everything_config({}) }

      it 'raises' do
        expect { described_class.validate!('url' => 'ftp://example.com/x') }
          .to raise_error(Bulkrax::UnsafeCloudSourceError, /unsupported source scheme/)
      end

      it 'does not echo the rejected url or scheme into the error message' do
        expect { described_class.validate!('url' => 'ftp://attacker.example/secret-path') }
          .to raise_error(Bulkrax::UnsafeCloudSourceError) { |e| expect(e.message).not_to match(/attacker|secret-path|ftp/i) }
      end
    end

    context 'file: sources' do
      let(:root) { File.realpath(Dir.mktmpdir) }

      after { FileUtils.rm_rf(root) }

      context 'when the filesystem provider is not configured' do
        before { stub_browse_everything_config({}) }

        it 'raises even for a path that would otherwise be valid' do
          target = File.join(root, 'a.pdf')
          File.write(target, 'x')

          expect { described_class.validate!('url' => "file://#{target}") }
            .to raise_error(Bulkrax::UnsafeCloudSourceError, /not configured/)
        end
      end

      context 'when the filesystem provider is configured' do
        before { stub_browse_everything_config(file_system: { home: root }) }

        it 'accepts a source inside the configured root' do
          target = File.join(root, 'a.pdf')
          File.write(target, 'x')

          expect(described_class.validate!('url' => "file://#{target}")).to be true
        end

        it 'rejects a source outside the configured root' do
          outside = File.realpath(Dir.mktmpdir)
          begin
            target = File.join(outside, 'secret.pdf')
            File.write(target, 'x')

            expect { described_class.validate!('url' => "file://#{target}") }
              .to raise_error(Bulkrax::UnsafeCloudSourceError)
          ensure
            FileUtils.rm_rf(outside)
          end
        end

        it 'rejects a traversal attempt relative to the root' do
          expect { described_class.validate!('url' => "file://#{root}/../../etc/passwd") }
            .to raise_error(Bulkrax::UnsafeCloudSourceError)
        end

        it 'rejects a file: url with a remote authority' do
          expect { described_class.validate!('url' => "file://attacker.example#{root}/a.pdf") }
            .to raise_error(Bulkrax::UnsafeCloudSourceError, /remote host/)
        end

        it 'does not echo the rejected filesystem path into the error message' do
          outside = File.realpath(Dir.mktmpdir)
          begin
            secret_path = File.join(outside, 'super-secret-filename.pdf')
            File.write(secret_path, 'x')

            expect { described_class.validate!('url' => "file://#{secret_path}") }
              .to raise_error(Bulkrax::UnsafeCloudSourceError) { |e| expect(e.message).not_to include('super-secret-filename') }
          ensure
            FileUtils.rm_rf(outside)
          end
        end
      end
    end

    context 'http(s) sources' do
      context 'when no remote provider is configured (filesystem-only setup)' do
        before { stub_browse_everything_config(file_system: { home: '/tmp' }) }

        it 'rejects a forged http(s) selection' do
          expect { described_class.validate!('url' => 'https://example.com/file.pdf') }
            .to raise_error(Bulkrax::UnsafeCloudSourceError, /no remote cloud provider/)
        end
      end

      context 'when a remote provider is configured' do
        before { stub_browse_everything_config(box: { client_id: 'abc' }) }

        it 'rejects a url with no host, with an accurate message (the url is missing a host, not forbidden from having one)' do
          expect { described_class.validate!('url' => 'https:///no-host-here.pdf') }
            .to raise_error(Bulkrax::UnsafeCloudSourceError, /must include a host/)
        end

        it 'rejects a url with embedded credentials' do
          expect { described_class.validate!('url' => 'https://user:pass@example.com/file.pdf') }
            .to raise_error(Bulkrax::UnsafeCloudSourceError, /credentials/)
        end

        it 'strips a caller-supplied Host header before connecting' do
          allow(SsrfFilter).to receive(:head)
          described_class.validate!('url' => 'https://example.com/file.pdf', 'headers' => { 'Host' => 'evil.example', 'X-Foo' => 'bar' })

          expect(SsrfFilter).to have_received(:head).with('https://example.com/file.pdf', headers: { 'X-Foo' => 'bar' }, max_redirects: 0)
        end

        it 'disables redirects' do
          allow(SsrfFilter).to receive(:head)
          described_class.validate!('url' => 'https://example.com/file.pdf')

          expect(SsrfFilter).to have_received(:head).with(anything, hash_including(max_redirects: 0))
        end

        # No mocking: SsrfFilter resolves 'localhost' via real DNS/hosts resolution to a
        # loopback address and rejects it before ever opening a socket, proving the
        # check is enforced at connection time rather than by a hostname regex.
        it 'rejects a loopback host at connection time' do
          expect { described_class.validate!('url' => 'http://localhost:1/x') }
            .to raise_error(Bulkrax::UnsafeCloudSourceError, /blocked unsafe remote source/)
        end

        it 'rejects a link-local/metadata host at connection time' do
          expect { described_class.validate!('url' => 'http://169.254.169.254/latest/meta-data/') }
            .to raise_error(Bulkrax::UnsafeCloudSourceError, /blocked unsafe remote source/)
        end

        # The tests above prove the *rejection* path for real: a genuinely
        # private/loopback address is rejected by SsrfFilter's own
        # resolver + blacklist, no mocking involved. SsrfFilter's
        # blacklist makes it impossible to also prove the *success* path
        # against a real private test server — any address we could run
        # locally is exactly what it's designed to reject. So these tests
        # stub only DNS resolution (hostname -> a real, non-reserved
        # public IP, same injection point SsrfFilter's own DEFAULT_RESOLVER
        # uses) and let WebMock intercept the resulting Net::HTTP socket —
        # SsrfFilter's resolve, blacklist-check, redirect-handling, and
        # header-assignment code all still run for real and unmocked.
        context 'against real (unstubbed) SsrfFilter, with only DNS resolution controlled' do
          let(:fake_public_ip) { '8.8.8.8' }
          let(:host) { 'cloud-provider.example.test' }
          let(:url) { "http://#{host}/file.pdf" }
          # Support URI-rewriting and connection-pinning ssrf_filter releases.
          let(:head_url) { %r{\Ahttp://(?:#{Regexp.escape(host)}|#{Regexp.escape(fake_public_ip)})/file\.pdf\z} }

          before { allow(Resolv).to receive(:getaddresses).with(host).and_return([fake_public_ip]) }

          it 'succeeds end-to-end for a permitted remote source (the positive path still works)' do
            stub_request(:head, head_url).to_return(status: 200)

            expect(described_class.validate!('url' => url)).to be true
          end

          it 'really does reject a redirect response rather than following it to a different host' do
            stub_request(:head, head_url)
              .to_return(status: 302, headers: { 'Location' => 'http://attacker.example/steal-credentials' })

            expect { described_class.validate!('url' => url) }
              .to raise_error(Bulkrax::UnsafeCloudSourceError, /blocked unsafe remote source/)
          end

          it 'never sends a caller-supplied Host header on the real outgoing request' do
            stub = stub_request(:head, head_url)
                   .with { |req| req.headers['Host'] != 'evil.example' }
                   .to_return(status: 200)

            described_class.validate!('url' => url, 'headers' => { 'Host' => 'evil.example' })

            expect(stub).to have_been_requested
          end

          it 'still forwards a legitimate provider auth header on the real outgoing request' do
            stub = stub_request(:head, head_url)
                   .with(headers: { 'Authorization' => 'Bearer legit-token' })
                   .to_return(status: 200)

            described_class.validate!('url' => url, 'auth_header' => { 'Authorization' => 'Bearer legit-token' })

            expect(stub).to have_been_requested
          end
        end
      end
    end
  end
end
