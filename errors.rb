#
# Error handling.
#
error MyAnimeList::NetworkError do
  details = "Exception message: #{request.env['sinatra.error'].message}"
  case params[:format]
  when 'xml'
    "<error><code>network-error</code><details>#{details}</details></error>"
  else
    { :error => 'network-error', :details => details }.to_json
  end
end

error MyAnimeList::UpdateError do
  details = "Exception message: #{request.env['sinatra.error'].message}"
  case params[:format]
  when 'xml'
    "<error><code>anime-update-error</code><details>#{details}</details></error>"
  else
    { :error => 'anime-update-error', :details => details }.to_json
  end
end

error MyAnimeList::UnknownError do
  details = "Exception message: #{request.env['sinatra.error'].message}"
  case params[:format]
  when 'xml'
    "<error><code>unknown-error</code><details>#{details}</details></error>"
  else
    { :error => 'unknown-error', :details => details }.to_json
  end
end

error do
  details = "Exception message: #{request.env['sinatra.error'].message}"
  case params[:format]
  when 'xml'
    "<error><code>unknown-error</code><details>#{details}</details></error>"
  else
    { :error => 'unknown-error', :details => details }.to_json
  end
end

not_found do
  if response.content_type == JSON_RESPONSE_MIME_TYPE
    { :error => response.body }.to_json
  else "<error><code>#{response.body}</code></error>"
  end
end