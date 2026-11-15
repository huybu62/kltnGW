# Henge: Identification and Specs for Comparison with Sidecar

## Q1. What candidates named "Henge" exist, and which one is the "emulator Henge"?

### Takeaway
**High confidence:** "emulator Henge" is **Henge by Leviidev** (github.com/Leviidev/Henge). It is a free, open-source (GPL-2.0-or-later) app that **emulates/installs macOS on an iPhone or iPad**, so no Mac is needed. Version 0.1 came out on 6 Nov 2026 and drew wide press coverage. It is **not** a second-display or screen-extension tool. The only other "Henge" is Henge Docks, a maker of hardware MacBook docks, and it has nothing to do with emulation.

### Cited Findings
- **Candidate 1: Henge (Leviidev), the macOS-on-iPhone/iPad emulator.** The repo tagline is "macOS on your iPhone and iPad". At fetch time (Nov 2026) the repo had about 2.3k stars, 197 forks and 445 commits. The developer's site is itslevii.dev — [GitHub Leviidev/Henge](https://github.com/Leviidev/Henge)
- Releases: **0.1 (06 Nov)**, "The first release of Henge, which runs macOS on iPhone and iPad without a Mac"; **0.2 (07 Nov)**; **0.3 (10 Nov)** — [GitHub releases](https://github.com/Leviidev/Henge/releases). The year 2026 comes from the repo copyright and a Japanese news URL dated 2026-11 — [smhn.info](https://smhn.info/202611-henge-macos-emulator-iphone-ipad-release)
- News outlets call it an "emulator". Russian coverage: "На GitHub вышел эмулятор Henge, позволяющий запустить macOS на iPhone и iPad" — [Metaratings](https://cybersport.metaratings.ru/news/na-github-vyshel-emulyator-henge-pozvolyayushii-zapustit-macos-na-iphone-i-ipad-669116/). Other coverage: [iThinkDiff "This App Runs macOS on iPhone and iPad"](https://www.ithinkdiff.com/henge-macos-on-iphone-ipad/), [OSNews "macOS made to run on iPhone"](https://www.osnews.com/story/143088/macos-made-to-run-on-iphone/). Only search snippets were available for these three; the site fetches failed in this session.
- **Candidate 2: Henge Docks**, a hardware maker of vertical and horizontal MacBook docks / port replicators (2012 onward). Brydge acquired it in 2019. The Brydge MacBook Vertical Dock is "the latest incarnation of what used to be Henge Docks" — [9to5Mac](https://9to5mac.com/2021/04/09/brydge-macbook-vertical-dock/); [MacRumors forum: Brydge acquires Henge Docks](https://forums.macrumors.com/threads/keyboard-maker-brydge-acquires-henge-docks.2196460); [TNW 2012](https://thenextweb.com/news/the-henge-dock-holds-your-macbook-air-beautifully-vertical). CDW lists several Henge models as discontinued in 2019 — [CDW](https://www.cdw.com/product/henge-docks-13-macbook-pro-with-retina-display-port-replicator/3419944)
- Searches turned up **no** iPad/Mac second-display or virtual-display app named Henge, on the App Store or on GitHub (searches for "Henge iPad second display Mac app" and "Henge github virtual display macOS" only returned Sidecar, Duet, Luna, Air Display, BetterDummy/BetterDisplay, OpenDisplay and similar) — [MacRumors how-to](https://www.macrumors.com/how-to/use-your-ipad-as-a-second-mac-monitor); [OpenDisplay](https://awesome.ecosyste.ms/projects/github.com%2Fpeetzweg%2Fopendisplay)

### Inferences
- The user's phrase "emulator henge" matches Leviidev's Henge almost word for word, since it is described everywhere as a macOS emulator for iPhone/iPad. It also went viral in November 2026, right around when the user asked. Henge Docks does not fit the word "emulator" and has not been sold under that name since about 2019.
- **Comparing it with Sidecar crosses categories.** Sidecar and the user's ScreenBridge **stream or extend a real Mac's display** to the iPad. Henge **runs a whole emulated Mac on the iPad itself**, with no Mac required. The fair way to compare them is "ways to get a Mac desktop or Mac apps onto an iPad": local emulation (Henge) versus remote display/extension (Sidecar, ScreenBridge, Duet, Luna).
- Henge Docks is only loosely relevant, as clamshell mode with an external monitor. It has nothing to do with the user's app.

### Gaps
- I could not read iThinkDiff, OSNews or smhn.info in full because the hosts were blocked in this session. Only search snippets were used.
- The user did not say which Henge they meant. The identification is inferred, though I am highly confident in it.

## Q2. Henge (Leviidev): detailed specs

### Takeaway
Henge is an experimental, sideloaded app that uses JIT, and it requires an A14/M1 or newer chip and iOS 17 or later. It runs macOS Sequoia, Sonoma, Ventura, Tahoe or macOS 27 as a guest. The guest gets 1–16 GB of RAM, a virtual GPU replayed through Metal, a display at 60 Hz or 120 Hz (ProMotion) with an optional 30 Hz mode, and USB-C output to an external monitor. Input is touch-as-trackpad plus a keyboard/mouse. Apple Account sign-in inside the guest **fails**. It is slower than a real Mac. It is free and cannot be distributed through the App Store.

### Cited Findings
**What it is and how it works**
- It does not use QEMU or Virtualization.framework, because iOS gives apps no hypervisor. Henge runs the Mac's arm64 code with its own JIT, MMU and emulated devices — [GitHub README](https://github.com/Leviidev/Henge)
- It downloads Apple's restore image and installs macOS the way a Mac would, without needing a Mac. The README says nothing is decrypted or patched — [GitHub README](https://github.com/Leviidev/Henge)
- Graphics go through a virtual GPU whose commands Henge replays with Metal — [GitHub README](https://github.com/Leviidev/Henge)

**Platforms and requirements**
- iOS/iPadOS 17 or later; A14 or M1 or newer — [GitHub README](https://github.com/Leviidev/Henge)
- JIT is required. Options: StikDebug, TrollStore (up to iOS 17.0), TrollStore Lite (needs a jailbreak), a jailbreak, or the built-in StikJIT helper on iOS 26 or later — [GitHub README](https://github.com/Leviidev/Henge)
- Storage: about 43 GB free for Sequoia (a 17 GB download plus 26 GB for the Mac). Sonoma is a 14.1 GB download and Ventura 12.3 GB — [GitHub README](https://github.com/Leviidev/Henge); [Releases 0.3](https://github.com/Leviidev/Henge/releases)
- Guest RAM: 1–16 GB is selectable from 0.2 onward. The README lists 4, 6 or 8 GB, and the increased-memory-limit entitlement is optional — [Releases 0.2](https://github.com/Leviidev/Henge/releases); [README](https://github.com/Leviidev/Henge)
- Guest macOS versions: Sequoia 15.6.1 is the main option. Tahoe 26.6.2 runs, but first setup is slow. macOS 27.2 runs but is the slowest, and Safari pages may stay blank. Sonoma 14.6.1 and Ventura 13.6 run. Monterey installs but its desktop never appears — [GitHub README](https://github.com/Leviidev/Henge)
- Testing: the README says it has been tested mainly on an iPhone 17 Pro and that "iPad support has not yet run on a real iPad". The 0.2 notes say contributors tested the iPad changes on their own iPads — [README](https://github.com/Leviidev/Henge); [Releases 0.2](https://github.com/Leviidev/Henge/releases). *The two sources disagree because the README lags behind the release notes.*

**Apple ID**
- Henge needs no Apple ID to work, although sideload signing can use a free Apple developer team (0.2). **Signing in to an Apple Account inside the guest macOS fails with a verification error** — [README](https://github.com/Leviidev/Henge); [Releases 0.2](https://github.com/Leviidev/Henge/releases)

**Display, resolution and refresh rate**
- On iPad, a new Mac gets a screen that matches the iPad's shape, with no black bars. iPad has "Retina" and "Performance" screen modes. On squarer iPhones the Mac fills the screen edge to edge — [README](https://github.com/Leviidev/Henge); [Releases 0.2](https://github.com/Leviidev/Henge/releases)
- Refresh rate: Settings › Performance offers 60 Hz, or 120 Hz on ProMotion devices (0.2). Version 0.3 added a 30 Hz option and a "Game Mode" — [Releases](https://github.com/Leviidev/Henge/releases)
- Colour: 0.2 fixed washed-out colours and colour-matches the iPad's P3 screen — [Releases 0.2](https://github.com/Leviidev/Henge/releases)
- External display: the Mac can drive an external display over USB-C, using a video-capable cable or a USB-C/HDMI dock. The phone or tablet stays as the trackpad and keyboard. This is confirmed on an iPhone 17 Pro running iOS 27. An older route for iOS 17–26 exists but had not been hardware-tested when the README was written — [README](https://github.com/Leviidev/Henge); [Releases 0.2](https://github.com/Leviidev/Henge/releases)
- No exact pixel resolution figures are published.

**Latency, codec and connection**
- There is no streaming codec and no network link. Everything renders locally on the device, through the virtual GPU and Metal replay — [README](https://github.com/Leviidev/Henge)
- Performance: Sequoia reaches the lock screen in about 15 s on an iPhone 17 Pro, and Discord opens in about 15 s. Apps launch more slowly for the first minutes after login. It is "slower than a real Mac" — [README](https://github.com/Leviidev/Henge); [Releases 0.1](https://github.com/Leviidev/Henge/releases)

**Input**
- The touchscreen acts as a Magic Trackpad 2, with two-finger scrolling and three-finger swipes for Spaces and Mission Control. Optional: volume up clicks, volume down right-clicks, hold to drag. An accessory key row adds Esc, Tab, Control, Option and Command — [README](https://github.com/Leviidev/Henge)
- A Magic Keyboard or Bluetooth keyboard and mouse connect directly on iPad. A physical Magic Trackpad 2 is supported from 0.3, and mouse right/middle buttons can be swapped. A sharper pointer has a size setting (0.2). iPadOS reserves some shortcuts, such as Cmd-Tab — [README](https://github.com/Leviidev/Henge); [Releases](https://github.com/Leviidev/Henge/releases)
- Apple Pencil: not mentioned.

**Audio:** not mentioned in the README or release notes. Sonoma video playback is supported from 0.3, but audio is not stated — [Releases 0.3](https://github.com/Leviidev/Henge/releases)

**Networking and sharing**
- The build uses libslirp for networking. From 0.3, web lookups use the device's DNS — [README](https://github.com/Leviidev/Henge); [Releases 0.3](https://github.com/Leviidev/Henge/releases)
- Clipboard copy and paste works between the guest Mac and the device. A shared folder appears in Files › Henge › Shared and in the Mac's home folder. Setup needs a Terminal command in the guest, with a US keyboard layout. A `henge-agent` needs local network permission — [README](https://github.com/Leviidev/Henge)

**Multiple instances and background behavior**
- Only one Mac can start per launch; Henge must be restarted to start another — [README](https://github.com/Leviidev/Henge)
- From 0.3, downloads continue after Henge is closed, and Macs shut down and restart properly — [Releases 0.3](https://github.com/Leviidev/Henge/releases). Nothing is documented about whether the VM keeps running in the background.

**Price and distribution**
- Free and open source under GPL-2.0-or-later. It includes usbmuxd and Husk code, and the README states it cannot ship on the App Store — [README](https://github.com/Leviidev/Henge)
- Install: Henge.ipa through SideStore or AltStore (with its own source feed, repo.json, from 0.3), Henge.tipa through TrollStore or TrollStore Lite, or a build from source with Xcode 27 or later and xcodegen — [README](https://github.com/Leviidev/Henge). Sideloadly on its own may not grant the needed JIT and memory entitlements (search snippet) — [iThinkDiff](https://www.ithinkdiff.com/henge-macos-on-iphone-ipad/)

**Known limitations**
- Apple Account sign-in fails. Untested apps may draw incorrectly; tested apps are Safari, Chrome, Firefox, VS Code and Discord. Sonoma dynamic wallpapers can freeze screen updates. Ventura's Dock Calendar icon has no date. Only one VM runs per launch — [README](https://github.com/Leviidev/Henge)

### Inferences
- Henge versus Sidecar: Sidecar needs a real Mac plus the same Apple ID on both devices, and **extends** that Mac's screen. Henge needs **no Mac** and no Apple ID, but it is a slow, experimental emulated Mac that needs JIT and sideloading. It is not an alternative for someone who already owns a Mac and wants a second display. The relevant comparison axes are use-case, dependence on a Mac, performance, Apple ID, distribution (App Store vs sideload), and maturity (0.x, released Nov 2026).
- Henge's 120 Hz option is a local render rate, not a streamed refresh rate, so it is not directly comparable to Sidecar's frame rate.

### Gaps
- No independent hands-on review or benchmark was found (news coverage only).
- No data on audio, Apple Pencil, exact resolution, input latency, or GPU performance numbers.

## Q3. Well-known screen-extension alternatives the user might have meant

### Takeaway
None of these is called Henge. They are the real peers to Sidecar and ScreenBridge. The specs below come from vendor pages and older articles. Current 2026 prices and refresh rates could not be verified within this research budget, so treat them as provisional.

### Cited Findings
- **Sidecar (Apple, built in):** Mac and iPad must be signed in to the same Apple ID with two-factor authentication. Managed Apple IDs are not supported. Wireless range is within 10 m, with Bluetooth, Wi-Fi and Handoff on. A wired mode exists; to switch from wired to wireless, disconnect first. Apple Pencil is optional, and double-tap works on 2nd-generation Pencils — [Apple support (archived HT210380)](https://webcf.waybackmachine.org/web/20220315052433/https://support.apple.com/en-us/HT210380); [Sidecar Tech Brief Oct 2019](https://www.apple.com/macos/big-sur/docs/Sidecar_Tech_Brief_Oct_2019.pdf); [Apple Mac help](https://support.apple.com/guide/mac-help/mchlf3c6f7ae)
- **Luna Display (Astropad):** a hardware dongle for wireless iPad/Mac second screens. Astropad's shop lists it at $89.99 regular price; Cult of Mac reported $79.99 earlier. Astropad's own comparison claims **16 ms latency for Luna vs 32 ms for Duet** (vendor claim from a competitor). It supports touch, external keyboards and Apple Pencil — [Astropad shop](https://shop.astropad.com/collections/luna-display-mac-and-pc/products/luna-display); [Astropad: Luna vs Duet](https://astropad.com/luna-display-versus-duet-display/); [Cult of Mac](https://www.cultofmac.com/news/luna-display-3-0-update-ipad-mac-external-screen)
- **Duet Display:** software only, wired (USB-C/Lightning) and wireless. Pencil pressure and tilt are on the Pro tier. A Feb 2026 update added a customizable pressure curve and "predictive line" — [iClarified, Feb 6 2026](https://www.iclarified.com/60637/duet-display-gets-customizable-pressure-curve-predictive-line-advanced-gesture-control-features); [MacRumors 2016](https://www.macrumors.com/2016/10/25/duet-display-for-ipad-gains-pro-drawing-features/); [AlternativeTo](https://www.alternativeto.net/software/duet-display/)
- **Splashtop Wired XDisplay:** paid and proprietary. It runs a free agent on Mac or PC and connects the iPad by cable. Splashtop claims 1080p or Retina at 60 fps — [AlternativeTo](https://alternativeto.net/software/splashtop-wired-xdisplay)
- **Spacedesk:** **Windows host only**, so it does not work as a Mac host — [AlternativeTo](https://alternativeto.net/software/spacedesk/?platform=mac)
- **Deskreen:** free and open source. It runs on a Mac, Windows or Linux host and shows the screen in any modern browser, with nothing to install on the client — [AlternativeTo](https://alternativeto.net/software/spacedesk/)
- **BetterDisplay / BetterDummy:** macOS virtual (dummy) display creation, used for HiDPI and headless setups. Open-source/macOS virtual-display projects such as OpenDisplay rely on the private `CGVirtualDisplay` API — [BetterDummy GitHub](https://github.com/Brezel31/BetterDummy); [OpenDisplay](https://awesome.ecosyste.ms/projects/github.com%2Fpeetzweg%2Fopendisplay)

### Inferences
- If the user's ScreenBridge creates a virtual display on the Mac (likely through `CGVirtualDisplay`) and streams it to the iPad, its closest technical relatives are OpenDisplay, Duet, Splashtop and Luna, not Henge. Its main advantage over Sidecar is likely not needing an Apple ID or a supported-hardware list, which is the same pitch Duet and Luna make.

### Gaps
- No verified 2026 prices or max Hz figures for Duet, Luna or Splashtop. No independent latency benchmarks; the Astropad numbers are a competitor's claims.
- BetterDisplay's current Sidecar/streaming features and price were not retrieved.
- I did not confirm whether Sidecar's frame rate is 60 Hz, or anything about ProMotion support, from an Apple primary source.
