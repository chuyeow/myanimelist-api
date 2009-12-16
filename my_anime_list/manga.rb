module MyAnimeList
  class Manga
    attr_accessor :id, :title, :rank, :popularity_rank, :image_url, :volumes, :chapters,
                  :members_score, :members_count, :favorited_count, :synopsis
    attr_reader :status
    attr_writer :genres, :other_titles, :anime_adaptations, :related_manga

    # These attributes are specific to a user-manga pair.
    attr_accessor :volumes_read, :chapters_read, :score
    attr_reader :read_status

    def status=(value)
      @status = case value
      when /finished/i
        :finished
      when /publishing/i
        :publishing
      when /not yet published/i
        :"Not yet published"
      else
        :finished
      end
    end

    def other_titles
      @other_titles ||= {}
    end

  end
end