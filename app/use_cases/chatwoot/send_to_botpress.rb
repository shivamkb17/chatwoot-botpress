require 'faraday'
require 'net/http'
require 'uri'
require 'json'

class Chatwoot::SendToBotpress < Micro::Case
  attributes :event
  attributes :botpress_endpoint
  attributes :botpress_bot_id

  def call!
    conversation_id = event['conversation']['id']
    if (
      event['content_type'] == 'input_select' &&
      event['content_attributes']['submitted_values'].respond_to?(:first)
    )
      message_content = event['content_attributes']['submitted_values'].first['value']
    else
      message_content = event['content']
    end
    message_content = determine_message_content(event)

    url = "#{botpress_endpoint}/api/v1/bots/#{botpress_bot_id}/converse/#{conversation_id}"

    body = {
      'text': message_content,
      'type': 'text',
      'metadata': {
        'event': event
      }
    }

    response = Faraday.post(url, body.to_json, {'Content-Type': 'application/json'})
    handle_response(response)
  end

  private

  def handle_response(response)
    if response.status == 200
      Success(result: JSON.parse(response.body))
    elsif response.status == 404 && response.body.include?('Invalid Bot ID')
      Failure(result: { message: 'Invalid Bot ID' })
    else
      Failure(result: { message: 'Invalid botpress endpoint' })
    end
  end

  def determine_message_content(event)
    if event.dig('attachments')&.any? { |attachment| attachment['file_type'] == 'location' }
      handle_location(event)
    elsif event.dig('attachments')&.any? { |attachment| attachment['file_type'] == 'audio' }
      handle_audio(event)
    else
      event['content'] || ""
    end
  end

  def handle_location(event)
    location = event['attachments'].find { |attachment| attachment['file_type'] == 'location' }
    "#{location['coordinates_lat']}, #{location['coordinates_long']}"
  end

  def handle_audio(event)
    audio_url = event['attachments'].find { |att| att['file_type'] == 'audio' }['data_url']
    transcribe_audio(audio_url)
  end

  def transcribe_audio(audio_url)
    uri = URI("http://191.36.227.60:9005/transcribe?file_url=#{URI.encode_www_form_component(audio_url)}")
    # uri = URI("http://192.168.1.168:9005/transcribe?file_url=#{URI.encode_www_form_component(audio_url)}")
    request = Net::HTTP::Post.new(uri)
    request['Accept'] = 'application/json'

    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    result = JSON.parse(response.body)
    result['transcriptions'].join(" ")
  rescue StandardError => e
    Rails.logger.error("Transcription error: #{e.message}")
    nil
  end
end
