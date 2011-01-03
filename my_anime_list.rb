require 'curb'
require 'nokogiri'

require './my_anime_list/rack'
require './my_anime_list/user'
require './my_anime_list/anime'
require './my_anime_list/anime_list'
require './my_anime_list/manga'
require './my_anime_list/manga_list'

module MyAnimeList

  # Raised when there're any network errors.
  class NetworkError < StandardError
    attr_accessor :original_exception

    def initialize(message, original_exception = nil)
      @message = message
      @original_exception = original_exception
      super(message)
    end
    def to_s; @message; end
  end

  # Raised when there's an error updating an anime/manga.
  class UpdateError < StandardError
    attr_accessor :original_exception

    def initialize(message, original_exception = nil)
      @message = message
      @original_exception = original_exception
      super(message)
    end
    def to_s; @message; end
  end

  class NotFoundError < StandardError
    attr_accessor :original_exception

    def initialize(message, original_exception = nil)
      @message = message
      @original_exception = original_exception
      super(message)
    end
    def to_s; @message; end
  end

  # Raised when an error we didn't expect occurs.
  class UnknownError < StandardError
    attr_accessor :original_exception

    def initialize(message, original_exception = nil)
      @message = message
      @original_exception = original_exception
      super(message)
    end
    def to_s; @message; end
  end

end