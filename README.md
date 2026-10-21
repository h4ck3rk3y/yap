# yap

A macOS menu bar app that shows, live, how much you're talking compared with the other person on a call, and nudges you when you've been going too long.

It works like Granola: **your mic is you, system audio is them**. Yap doesn't transcribe or record anything. It only measures how loud each stream is, ten times a second.

## Run

```sh
./build.sh --run       # build + launch from ./build
./build.sh --install   # build + copy to ~/Applications and launch
swift test             # core logic tests
swift scripts/make-icon.swift  # regenerate Resources/AppIcon.icns
```

On first start, macOS asks for **Microphone** and **Screen & System Audio Recording** access. The second one is how Yap hears the other side. Without it, Yap still times your turns but can't show a ratio.

## What it does

- **Menu bar:** while a call is live it shows `🟢 42%`, your share of the talking. Once you've been talking for 20s it switches to `🗣 0:47`.
- **Auto start/stop:** starts when another app (Zoom, Meet, Teams, Slack, Granola…) uses the mic for 4s or more. Stops 12s after the mic is released.
- **Nudges:** a floating pill at the top of the screen. It's hidden from screen sharing.
  - 🫁 *Take a breath* after 60s of you talking without a break
  - 🤐 *Pause. Ask them a question.* after 90s
  - 👂 *Time to listen* when you've had 70% or more of the last 5 minutes (at most once every 5 min)
- **History:** each call's stats are saved to `~/Library/Application Support/Yap/sessions.json`.

A "turn" survives short pauses and the other person saying "mhm". It ends when they speak for 1s or more, or when you pause for 3s.

## Tips

- Headphones work best. On laptop speakers, Yap ignores mic sound while the other side is talking (so their voice from your speakers isn't counted as you), or you can turn on *Echo cancellation* in Settings.
- Any other sound your Mac plays during a call (YouTube, music) counts as "them".

## License

MIT
