# news-fetcher

A tiny Ruby script that:

- fetches top stories from Hacker News
- filters for higher-signal items (currently `score >= 50`)
- asks OpenAI to pick and summarize the 10 most important items (Markdown, Russian)
- sends the digest to a Telegram chat

This is useful if you want a daily, curated tech/news digest delivered to Telegram without manually checking Hacker News.

## Setup

### Prerequisites

- Ruby (GitHub Actions uses **Ruby 3.2**)
- Bundler

### Local run

1. Install gems:

```bash
bundle install
```

2. Create a `.env` file (it is gitignored) with:

```bash
OPENAI_API_KEY=...
TG_TOKEN=...
TG_CHAT_ID=...
```

3. Run:

```bash
ruby digest.rb
```

### GitHub Actions (daily)

The workflow in `.github/workflows/daily_digest.yml` runs on a cron schedule and can also be started manually.

Add these repository secrets:

- `OPENAI_API_KEY`
- `TG_TOKEN`
- `TG_CHAT_ID`


