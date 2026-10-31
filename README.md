# Downstage Virtual Deck

A Stream Deck on your screen: Mini, Neo, 15 key, XL, +, + XL, or a custom grid, with keys, touch strip and dials.
It joins [Bitfocus Companion](https://bitfocus.io/companion) as a surface over its Satellite WebSocket (port 16623, Companion 4.0 or later).

- Type your Companion's address. The Mac app also finds a Downstage One on the network by itself; a typed address wins.
- Choose the deck's page in Companion, under Surfaces.
- `web/apps/virtual-deck.html` is the whole app, and it needs no server.

Build the Mac app with `macapp/build.sh` (Apple Silicon, needs Xcode). It writes `dist/`.
