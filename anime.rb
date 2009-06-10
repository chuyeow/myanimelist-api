class Anime
  attr_accessor :id, :title, :type, :episodes

  # These attributes are specific to a user-anime pair, probably should go into another model.
  attr_accessor :watched_episodes, :score, :watched_status

  def to_json
    {
      :id => id,
      :title => title,
      :type => type,
      :episodes => episodes,
      :watched_episodes => watched_episodes,
      :score => score,
      :watched_status => watched_status,
    }.to_json
  end
end