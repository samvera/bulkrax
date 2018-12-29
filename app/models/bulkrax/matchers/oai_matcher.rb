module Bulkrax
  module Matchers
    class OaiMatcher < ApplicationMatcher
      def parse_remote_files(src)
        {url: src}
      end

      def parse_language(src)
        l = LanguageList::LanguageInfo.find(src)
        return l ? l.name : src
      end

      def parse_types(src)
        src.to_s.titleize
      end

      def parse_format_original(src)
        src.to_s.titleize
      end

      def parse_format_digital(src)
        case src
        when 'application/pdf','pdf', 'PDF'
          'PDF'
        when 'image/jpeg', 'image/jpg', 'jpeg', 'jpg', 'JPEG', 'JPG'
          'JPEG'
        when 'image/tiff', 'image/tif', 'tiff', 'tif', 'TIFF', 'TIF'
          'TIFF'
        when 'image/jp2', 'jp2', 'JP2'
          'JP2'
        when 'image/png', 'png', 'PNG'
          'PNG'
        when 'image/gif', 'gif', 'GIF'
          'GIF'
        when 'video/mp4', 'mp4', 'MP4'
          'MP4'
        when 'video/ogg', 'ogg', 'OGG'
          'OGG'
        when 'video/vnd.avi', 'video/avi', 'avi', 'AVI'
          'AVI'
        when 'audio/aac', 'aac', 'AAC'
          'AAC'
        when 'audio/mp4', 'mp4', 'MP4'
          'MP4'
        when 'audio/mpeg', 'audio/mp3', 'audio/mpeg3', 'mpeg', 'MPEG', 'mp3', 'MP3', 'mpeg3', 'MPEG3'
          'MPEG'
        when 'audio/ogg', 'ogg', 'OGG'
          'OGG'
        when 'audio/aiff', 'aiff', 'AIFF'
          'AIFF'
        when 'audio/webm', 'webm', 'WEBM'
          'WEBM'
        when 'audio/wav', 'wav', 'WAV'
          'WAV'
        when 'text/csv', 'csv', 'CSV'
          'CSV'
        when 'text/html', 'html', 'HTML'
          'HTML'
        when 'text/rtf', 'rtf', 'RTF'
          'RTF'
        else
          src.to_s.titleize
        end
      end
    end
  end
end
