require "bundler/setup"

require "dotenv/load"
require "httpx"
require "openai"
require "json"
require "socket"

HN_TOP_URL = "https://hacker-news.firebaseio.com/v0/topstories.json"
HN_ITEM_URL = "https://hacker-news.firebaseio.com/v0/item/%s.json"

def env!(key)
  ENV[key] || abort("Missing ENV var #{key}. Set it in your shell or add it to a .env file.")
end

HTTP = HTTPX.with(ip_families: [Socket::AF_INET], resolver_class: :system)

def json_get!(url, label:)
  resp = HTTP.get(url)

  if resp.is_a?(HTTPX::Response) && resp.status == 200
    return resp.json
  end

  details = [label, url, resp.class.to_s]
  if resp.is_a?(HTTPX::ErrorResponse)
    details << resp.error.message
  elsif resp.respond_to?(:status)
    details << "status=#{resp.status}"
    details << resp.error.message if resp.respond_to?(:error) && resp.error
  end

  abort("Request failed: #{details.join(' | ')}")
end

OPENAI_TOKEN = env!("OPENAI_API_KEY")
TG_TOKEN = env!("TG_TOKEN")
TG_CHAT_ID = env!("TG_CHAT_ID")

# 1. Fetch top stories from Hacker News
puts "Fetching HN Top Stories..."
top_ids = json_get!(HN_TOP_URL, label: "HN topstories").first(50)

# 2. Fetch details of each story (asynchronously for speed)
puts "Fetching details..."
items = []
# HTTPX can make batch requests, which is very fast
responses = HTTP.get(*top_ids.map { |id| HN_ITEM_URL % id })

responses.each do |resp|
  next if resp.is_a?(HTTPX::ErrorResponse)
  next unless resp.status == 200
  item = resp.json
  next if item['score'].to_i < 50 
  items << { title: item['title'], url: item['url'], score: item['score'] }
end

puts "Found #{items.size} worthy stories."
exit if items.empty?

# 3. Prepare prompt for AI
prompt_list = items.map { |i| "- #{i[:title]} (Score: #{i[:score]}) - #{i[:url]}" }.join("\n")

system_prompt = <<~TEXT
  Ты технический журналист. 
  Твоя задача — отобрать из списка 5 самых важных новостей.
  Новости могут быть связаны со следующими темами:
  - Саморазвитие и рефлексия
  - Жизнь и смысл жизни
  - Мозг и его работа
  - ИИ и его влияние на нас и нашу жизнь
  - Программирование роботов и ИИ (если прямо про них, то только если связаны с поведением, развитием и рефлексией)
  - Творчество и генерация картинок
  Также выбери 2 новости которые кажутся нестандартными и интересными.
  
  Для каждой из 7 новостей:
  1. Напиши заголовок на русском (переведи или адаптируй).
  2. Кратко объясни суть (почему это важно или о чем там).
  3. Укажи оригинальную ссылку.

  Формат вывода: Markdown. Не пиши вступлений, сразу список.
TEXT

# 4. Ask GPT
puts "Asking AI..."
client = OpenAI::Client.new(access_token: OPENAI_TOKEN)
openai_response = nil
ai_summary = nil

max_attempts = 3
max_attempts.times do |i|
  attempt = i + 1

  begin
    openai_response = client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: prompt_list }
        ],
        temperature: 0.3,
      }
    )

    ai_summary = openai_response.dig("choices", 0, "message", "content")
    break if ai_summary.is_a?(String) && !ai_summary.strip.empty?

    raise "OpenAI response missing content"
  rescue => e
    raise if attempt >= max_attempts

    wait_s = 2**(attempt - 1) # 1, 2
    puts "OpenAI request failed (attempt #{attempt}/#{max_attempts}): #{e.class}: #{e.message}. Retrying in #{wait_s}s..."
    sleep wait_s
  end
end

# 5. Send to Telegram
puts "Sending to Telegram..."
tg_url = "https://api.telegram.org/bot#{TG_TOKEN}/sendMessage"
response = HTTP.post(
  tg_url,
  json: { chat_id: TG_CHAT_ID, text: ai_summary, parse_mode: "Markdown" }
)
if response.is_a?(HTTPX::Response) && response.status == 200
  puts "Message sent successfully"
else
  details = ["Message failed to send", response.class.to_s]
  details << "status=#{response.status}" if response.respond_to?(:status) && response.status
  details << response.error.message if response.respond_to?(:error) && response.error
  puts details.join(" | ")
end

puts "Done!"