import Foundation

/// Bundled list of common sites, so typing "tik" can offer "tiktok.com" without
/// any network lookup.
enum TopSites {
    static let domains: [String] = [
        // Social and messaging
        "tiktok.com", "instagram.com", "facebook.com", "x.com", "twitter.com",
        "reddit.com", "snapchat.com", "threads.net", "bsky.app", "mastodon.social",
        "linkedin.com", "pinterest.com", "tumblr.com", "discord.com", "whatsapp.com",
        "messenger.com", "telegram.org", "web.telegram.org", "slack.com", "vk.com",
        "weibo.com", "quora.com", "nextdoor.com", "clubhouse.com", "lemmy.world",
        // Video and streaming
        "youtube.com", "netflix.com", "twitch.tv", "hulu.com", "disneyplus.com",
        "primevideo.com", "max.com", "hbomax.com", "peacocktv.com", "paramountplus.com",
        "vimeo.com", "dailymotion.com", "crunchyroll.com", "funimation.com", "plex.tv",
        "bilibili.com", "iqiyi.com", "youku.com", "rumble.com", "kick.com",
        "tv.apple.com", "mubi.com", "criterionchannel.com", "tubitv.com", "pluto.tv",
        // Music and audio
        "spotify.com", "soundcloud.com", "music.apple.com", "bandcamp.com", "pandora.com",
        "tidal.com", "deezer.com", "last.fm", "audible.com", "podcasts.apple.com",
        // News and reading
        "news.ycombinator.com", "medium.com", "substack.com", "nytimes.com", "washingtonpost.com",
        "theguardian.com", "bbc.com", "cnn.com", "foxnews.com", "npr.org",
        "wsj.com", "bloomberg.com", "reuters.com", "apnews.com", "economist.com",
        "theverge.com", "arstechnica.com", "techcrunch.com", "wired.com", "engadget.com",
        "9to5mac.com", "macrumors.com", "hackernoon.com", "lifehacker.com", "vox.com",
        "buzzfeed.com", "vice.com", "theatlantic.com", "newyorker.com", "slate.com",
        "dailymail.co.uk", "nypost.com", "usatoday.com", "forbes.com", "businessinsider.com",
        // Shopping
        "amazon.com", "ebay.com", "etsy.com", "walmart.com", "target.com",
        "aliexpress.com", "temu.com", "shein.com", "wish.com", "bestbuy.com",
        "costco.com", "homedepot.com", "lowes.com", "wayfair.com", "ikea.com",
        "newegg.com", "chewy.com", "zappos.com", "nike.com", "apple.com",
        "shopify.com", "craigslist.org", "offerup.com", "mercari.com", "poshmark.com",
        // Games
        "steampowered.com", "store.steampowered.com", "epicgames.com", "roblox.com", "minecraft.net",
        "chess.com", "lichess.org", "itch.io", "gog.com", "battle.net",
        "playstation.com", "xbox.com", "nintendo.com", "ign.com", "gamespot.com",
        "polygon.com", "kotaku.com", "speedrun.com", "coolmathgames.com", "poki.com",
        "crazygames.com", "miniclip.com", "agar.io", "krunker.io", "slither.io",
        // Work, dev and productivity
        "github.com", "gitlab.com", "bitbucket.org", "stackoverflow.com", "stackexchange.com",
        "notion.so", "linear.app", "asana.com", "trello.com", "monday.com",
        "atlassian.net", "jira.com", "confluence.com", "figma.com", "canva.com",
        "docs.google.com", "drive.google.com", "sheets.google.com", "mail.google.com", "calendar.google.com",
        "google.com", "gmail.com", "outlook.com", "office.com", "onedrive.com",
        "dropbox.com", "box.com", "zoom.us", "meet.google.com", "teams.microsoft.com",
        "airtable.com", "clickup.com", "basecamp.com", "todoist.com", "evernote.com",
        "obsidian.md", "roamresearch.com", "miro.com", "loom.com", "calendly.com",
        // AI
        "chatgpt.com", "chat.openai.com", "openai.com", "claude.ai", "anthropic.com",
        "gemini.google.com", "perplexity.ai", "copilot.microsoft.com", "midjourney.com", "huggingface.co",
        "cursor.com", "replit.com", "v0.dev", "poe.com", "character.ai",
        // Learning and reference
        "wikipedia.org", "en.wikipedia.org", "coursera.org", "udemy.com", "edx.org",
        "khanacademy.org", "duolingo.com", "brilliant.org", "codecademy.com", "leetcode.com",
        "hackerrank.com", "kaggle.com", "arxiv.org", "scholar.google.com", "jstor.org",
        "wolframalpha.com", "goodreads.com", "archive.org", "gutenberg.org", "wikihow.com",
        // Finance
        "robinhood.com", "coinbase.com", "binance.com", "kraken.com", "tradingview.com",
        "fidelity.com", "schwab.com", "vanguard.com", "chase.com", "bankofamerica.com",
        "paypal.com", "venmo.com", "wise.com", "mint.com", "yahoo.com",
        "finance.yahoo.com", "marketwatch.com", "seekingalpha.com", "investing.com", "morningstar.com",
        // Travel, food, misc
        "booking.com", "airbnb.com", "expedia.com", "kayak.com", "tripadvisor.com",
        "uber.com", "lyft.com", "doordash.com", "ubereats.com", "grubhub.com",
        "yelp.com", "opentable.com", "maps.google.com", "waze.com", "zillow.com",
        "redfin.com", "indeed.com", "glassdoor.com", "levels.fyi", "weather.com",
        "espn.com", "nba.com", "nfl.com", "mlb.com", "fifa.com",
        "strava.com", "myfitnesspal.com", "webmd.com", "imdb.com", "letterboxd.com",
        "rottentomatoes.com", "fandom.com", "deviantart.com", "artstation.com", "behance.net",
        "dribbble.com", "unsplash.com", "giphy.com", "imgur.com", "9gag.com",
        "producthunt.com", "indiehackers.com", "hackaday.com", "instructables.com", "duckduckgo.com",
        "bing.com", "baidu.com", "yandex.com", "9anime.to", "onlyfans.com"
    ]

    /// Ranked suggestions for a partial query.
    ///
    /// Previously used domains win, then prefix matches, then substring matches,
    /// so typing "tik" surfaces "tiktok.com" ahead of unrelated sites.
    static func suggestions(for query: String, recents: [String], limit: Int = 6) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return Array(recents.prefix(limit)) }

        let stripped = DomainMatcher.strippingWWW(needle)
        var seen = Set<String>()
        var ranked: [(score: Int, domain: String)] = []

        func consider(_ domain: String, bonus: Int) {
            guard !seen.contains(domain) else { return }
            let score: Int
            if domain == stripped {
                score = 0
            } else if domain.hasPrefix(stripped) {
                score = 1
            } else if domain.split(separator: ".").contains(where: { $0.hasPrefix(stripped) }) {
                score = 2
            } else if domain.contains(stripped) {
                score = 3
            } else {
                return
            }
            seen.insert(domain)
            // Shorter domains are the likelier intent among equal matches.
            ranked.append((score * 100 + bonus + min(domain.count, 40), domain))
        }

        for domain in recents { consider(domain, bonus: -50) }
        for domain in domains { consider(domain, bonus: 0) }

        var result = ranked.sorted { $0.score < $1.score }.map(\.domain)

        // Always offer exactly what was typed when it is already a valid domain.
        if let normalized = DomainMatcher.normalize(userInput: needle), !result.contains(normalized) {
            result.insert(normalized, at: 0)
        }
        return Array(result.prefix(limit))
    }
}
