const Parser = require("rss-parser");
const axios = require("axios");
const crypto = require("crypto");

const RSS_URL = process.env.RSS_URL;
const BOT_TOKEN = process.env.BOT_TOKEN;
const CHANNEL_ID = process.env.CHANNEL_ID;

// default to 15 mins
const POLL_INTERVAL = parseInt(process.env.POLL_INTERVAL || "0.25") * 60 * 60 * 1000;

// skip if env not set
if (!process.env.BOT_TOKEN || !process.env.CHANNEL_ID || !process.env.RSS_URL) {
  console.log("env vars are required, skipping rss-bot.");
  process.exit(0);
}

const feedParser = new Parser();

// fetch start time is since 3 days ago
const StartTime = Date.now() - (3 * 24 * 60 * 60 * 1000)

// guid -> feed hash
const state = new Map();

/**
 * oldest → newest so messages stay in order
 * @typedef {{
 * title: string,
 * link: string,
 * pubDate: string,
 * content: string,
 * contentSnippet: string,
 * guid: string,
 * isoDate: string
 * }} Feed
 */

/**
 * Posts to telegram
 * @param {Feed} feed 
 */
async function sendTelegram(feed) {
  await axios.post(
    `https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`,
    {
      chat_id: CHANNEL_ID,
      text: `📰 *${feed.title}*\n*${feed.pubDate}*\n\n${feed.contentSnippet}\n\n${feed.link}`,
      parse_mode: "markdown"
    }
  );
}

async function checkFeed() {
  try {
    const result = await feedParser.parseURL(RSS_URL);

    /**
     * @type {Array<Feed>}
     */
    const feeds = [...result.items];

    for (const feed of feeds) {
        // skip if older than start time
        const feedTime = Date.parse(feed.isoDate);
        if (feedTime < StartTime) continue;
            
        const feedHash = crypto
            .createHash("sha256")
            .update(feed.content ?? "" + feed.contentSnippet ?? "")
            .digest("hex");

        // skip if already exists in state
        const prev = state.get(feed.guid);
        if (prev) continue;
        state.set(feed.guid, feedHash);

        // post to telegram
        await sendTelegram(feed).catch((e) => console.log("Telegram error:", e));
    }
  } catch (err) {
    console.error("Feed error:", err.message);
  }
}

function main() {
  setInterval(checkFeed, POLL_INTERVAL);
}

main()
    .then(() => {
        process.exit(0);
    })
    .catch((v) => {
        console.error(v, "\n");
        process.exit(1);
    });
