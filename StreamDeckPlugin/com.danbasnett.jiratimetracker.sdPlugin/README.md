# JiraTimeTracker Stream Deck Plugin

Control JiraTimeTracker from your Elgato Stream Deck.

## Actions

- **Toggle Timer** — Pause/resume the active timer
- **Pause / Resume** — Pause or resume the active timer
- **Stop & Log** — Stop the timer and log time to Jira

## Requirements

- JiraTimeTracker macOS app installed and running
- Stream Deck 6.7+ with Node.js 24+

## Building

```bash
cd StreamDeckPlugin
npm install
npm run build
```

## Installing

Copy the `.sdPlugin` folder to your Stream Deck plugins directory:

```bash
cp -r com.danbasnett.jiratimetracker.sdPlugin ~/Library/Application\ Support/com.elgato.StreamDeck/Plugins/
```

Then restart the Stream Deck app.

## How it works

The plugin sends URL scheme commands (`jiratimetracker://toggle`, `jiratimetracker://stop`) to the macOS app. The app handles the commands and updates the timer state.
