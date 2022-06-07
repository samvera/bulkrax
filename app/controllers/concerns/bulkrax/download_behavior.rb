# frozen_string_literal: true

module Bulkrax
  module DownloadBehavior
    # The following download code is based on
    # https://github.com/samvera/hydra-head/blob/master/hydra-core/app/controllers/concerns/hydra/controller/download_behavior.rb

    def file
      @file ||= File.open(file_path, 'r')
    end

    # Override this if you'd like a different filename
    # @return [String] the filename
    def file_name
      file_path.split('/').last
    end

    def download_content_type
      'application/zip'
    end

    def send_content
      response.headers['Accept-Ranges'] = 'bytes'
      if request.head?
        content_head
      else
        send_file_contents
      end
    end

    # Create some headers for the datastream
    def content_options
      { disposition: 'inline', type: download_content_type, filename: file_name }
    end

    # render an HTTP HEAD response
    def content_head
      response.headers['Content-Length'] = file.size
      head :ok, content_type: download_content_type
    end

    def send_file_contents
      self.status = 200
      prepare_file_headers
      send_file file
    end

    def prepare_file_headers
      send_file_headers! content_options
      response.headers['Content-Type'] = download_content_type
      response.headers['Content-Length'] ||= file.size.to_s
      # Prevent Rack::ETag from calculating a digest over body
      response.headers['Last-Modified'] = File.mtime(file_path).utc.strftime("%a, %d %b %Y %T GMT")
      self.content_type = download_content_type
    end
  end
end
