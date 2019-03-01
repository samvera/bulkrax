module Bulkrax
  class OaiMatcher < ApplicationMatcher
    def parse_collections(src)
      collection = Collection.where(title: [src]).first
      collection ||= Collection.create(title: [src], identifier: [src], collection_type_gid: Hyrax::CollectionType.find_or_create_default_collection_type.gid)
      {id: collection.id} if collection
    end
    def parse_remote_files(src)
      { url: src } if src.present?
    end

    def parse_language(src)
      l = LanguageList::LanguageInfo.find(src)
      l ? l.name : src
    end

    def parse_types(src)
      src.to_s.titleize
    end

    def parse_format_original(src)
      src.to_s.titleize
    end

    def parse_format_digital(src)
      case src.to_s.strip.downcase
      when 'application/pdf', 'pdf'
        'PDF'
      when 'image/jpeg', 'image/jpg', 'jpeg', 'jpg'
        'JPEG'
      when 'image/tiff', 'image/tif', 'tiff', 'tif'
        'TIFF'
      when 'image/jp2', 'jp2'
        'JP2'
      when 'image/png', 'png'
        'PNG'
      when 'image/gif', 'gif'
        'GIF'
      when 'video/mp4', 'mp4'
        'MP4'
      when 'video/ogg', 'ogg'
        'OGG'
      when 'video/vnd.avi', 'video/avi', 'avi'
        'AVI'
      when 'audio/aac', 'aac'
        'AAC'
      when 'audio/mpeg', 'audio/mp3', 'audio/mpeg3', 'mpeg', 'mp3', 'mpeg3'
        'MPEG'
      when 'audio/aiff', 'aiff'
        'AIFF'
      when 'audio/webm', 'webm'
        'WEBM'
      when 'audio/wav', 'wav'
        'WAV'
      when 'text/csv', 'csv'
        'CSV'
      when 'text/html', 'html'
        'HTML'
      when 'text/rtf', 'rtf'
        'RTF'
      else
        src.to_s.titleize
      end
    end
  end
end
