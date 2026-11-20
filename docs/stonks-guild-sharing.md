# Encore-Stonks guild sharing

Guildmates running Encore-Stonks share auction prices over the guild channel. It is **on by default** (share); `/stonksync receive` or `/stonksync off` turns it down.

The graph panel has **Share item** and **Share scan** buttons at the bottom right. Each puts a chat link into the chat you were last typing in (whisper, party, raid, guild, officer or a channel), or the selected whisper tab, ready to send with Enter. Guild chat when that was say, yell or emote, or you have not typed yet this session.

| Command | What it does |
| --- | --- |
| `/stonksync share` | Default. Share your scans and answer guildmates' login requests, and receive theirs |
| `/stonksync receive` | Receive only (you send just one small request at login) |
| `/stonksync off` | Nothing automatic is sent or received (chat links still work) |
| `/stonksync status` | Mode, how much guild data you hold, last login summary, muted players |
| `/stonksync perf` | Bytes and messages sent and received, worst frame time, sends in combat (should be 0) |
| `/stonksync lowend` | Stop receiving hourly guild scans (login summary and links still work) |
| `/stonksync mute <name>` / `unmute <name>` | Ignore a player's prices |
| `/stonksync link scan` | Put a link to your latest scan in the chat box |
| `/stonksync link item <item>` | Put a link to one item's price history in the chat box |
| `/stonksync history` | Open the History tab: when and from whom you received guild scans, login summaries and shared prices |

## How it works

- **Hourly scans.** The first player to finish a scan in a UTC hour claims that hour on the guild channel, waits 3 seconds for a crossing claim (lower hash wins), and broadcasts only the items whose price moved more than 1% or whose quantity changed since the last shared hour. Everyone else keeps their scan to themselves.
- **Login summary.** A minute after login, out of combat, the player sends `HELLO` with the hour of its last summary. Guildmates sharing data who are free and hold newer data wait 0 to 1 seconds when AFK, 1 to 5 otherwise (shorter for fresher data), and the first one sends `OFFER`; anyone who hears an offer stands down. The asker picks the best offer after 2 seconds (AFK first, then freshest) and sends `ACCEPT`. The summary comes by whisper, only for items that changed since the asker's last summary. If no block arrives for 60 seconds the asker keeps what it has and asks again from the next item. No offer within 15 seconds: retry after 1, 2, 4, 8 and 15 minutes.
- **Chat links.** Anyone can post a link; it travels as plain text (`[Stonks: Black Lotus #i13468]`) and players with Stonks see it as a link. Clicking asks for confirmation, and only then is the data requested by whisper. Posters only answer for links they posted in the last hour.

- **Sync history.** Every delivery you receive is logged per realm (`realm.syncLog`, last 30 days, at most 300 entries): hourly scans by sender and hour (closed by the sender's end message), login summaries (marked stopped when the sender goes quiet and someone else resumes), and shared items and scans. The graph window's History tab shows it; nothing about it is sent.

## Limits that keep it invisible

- At most 400 bytes a second sent, through ChatThrottleLib at its lowest priority when another addon has loaded it. On a refused send: back off 1, 2, 4 ... 60 seconds.
- Nothing is sent in combat, in instances, or within a minute of an auction house scan.
- The receive handler only checks the header and queues. Reading and saving happen in a work queue limited to 1 ms per frame (0.5 ms below 30 fps), and nothing in combat.
- At most 120 KB per sender per hour and 3,000 queued messages; the rest is dropped.

## Safety

- Received data is read only as numbers in a fixed 64-character format and range-checked; any bad field rejects the whole message. Nothing received is ever run or turned into arbitrary tables, and handlers run inside `pcall`.
- Only item ID, lowest price, quantity on sale and the hour are sent. Item names shown in links come from your own client; sender names are cleaned of escape codes.
- Prices more than 5x away from your own 14-day average (once you have 5 days of data) are not accepted. A sender with more than 30% such prices over 50 checks is muted automatically.

## Where received data goes

- `realm.guild[itemID]`: guild samples, same format as your own (`hour:price:qty;` base 36). Your own hour always wins; at most one guild sample per item per 4 hours unless the price moved more than 2%. Pruned with your kept days.
- `realm.baseline[itemID]`: the latest summary record per item (median, quartiles, 3/7/14-day averages, days, weekday and hour buckets). Charts blend it in and it fades out as your own days of data reach 20. It never goes into your own folded totals, so nothing is counted twice.

## Testing

`lua5.1 tools/stonks-sync/sim.lua` runs the real addon files in 200 simulated clients on a fake guild channel: wire format and rejection of bad input, login handshake (offers, AFK priority, full summary), resume after the sender logs off, one broadcast per hour with 4 scanners, no sends in combat, outlier rejection, chat links, and per-frame timing.

## Not done yet

- Category links and the automatic single-item question when you open an item with little history.
- Random-suffix items (`gr:` keys) are not shared; only plain item IDs are.
- There's no settings UI for the mode yet, only `/stonksync`.
