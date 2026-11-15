# Apple Sidecar (Mac to iPad second display), state as of Nov 2026

Research note (2026-11-15): WebFetch was blocked for support.apple.com, appleinsider.com, forums.macrumors.com and web.archive.org in this session. Most findings below come from search-result summaries of those pages, not from full-page reads. Apple's own Sidecar page (support.apple.com/en-us/102597) could not be opened directly. Its content is quoted only as search snippets surfaced it.

IMPORTANT CONTEXT: The current OS generation is macOS 27 "Golden Gate" / iPadOS 27, released 2026-09-14 ([9to5Mac](https://9to5mac.com/2026/09/09/apple-confirms-macos-27-golden-gate-launch-date-september-14/), [MacRumors](https://www.macrumors.com/2026/09/14/apple-releases-macos-golden-gate/)). macOS 15 Sequoia and macOS 26 Tahoe are now previous versions. macOS 27 is the biggest Sidecar change since launch, because it adds direct finger touch.

## 1. Requirements: Apple Account, 2FA, wireless/wired, distance

### Takeaway
Both devices must be signed in to the same Apple Account with two-factor authentication. Wireless use needs Bluetooth, Wi-Fi and Handoff on, with the devices within 10 m (30 ft). Wired use over USB needs the iPad to "trust" the Mac. A custom third-party app has no account lock-in, which is a clear point of difference.

### Cited Findings
- Both devices must be signed in with the same Apple Account using two-factor authentication — [Apple Support 102597 (via search snippet)](https://support.apple.com/en-lamr/102597); [UCSD ITSS guide](https://itss.ucsd.edu:443/TipsandTricks/Documents/Use%20iPad%20as%20second%20display%20for%20Mac.pdf)
- Wireless: devices within 10 meters (30 feet), with Bluetooth, Wi-Fi and Handoff turned on — [Apple Support 102597](https://support.apple.com/en-lamr/102597); [OWC blog (Sonoma)](https://eshop.macsales.com/blog/86999-how-to-connect-an-ipad-to-macos-sonoma-as-a-wireless-second-display-via-sidecar/)
- USB: the iPad must be set to trust the Mac — [Apple Support 102597](https://support.apple.com/en-lamr/102597)
- Wireless transport is AWDL (Apple Wireless Direct Link), the peer-to-peer Wi-Fi protocol also behind AirDrop and AirPlay. This is a secondary source — [healthy-network blog](https://healthy-network.pages.dev/blog/ethernet-vs-wifi-mac)
- Managed Apple IDs: sources conflict. Community and third-party sources say Sidecar does not support Managed Apple IDs. Apple's Platform Deployment Continuity guide lists Sidecar as working with a personal or a Managed Apple Account — [Apple Platform Support guide](https://support.apple.com/cs-cz/guide/platform-support/sup60beac13c/web); [Apple Community](https://discussions.apple.com/thread/254449723)
- iCloud 2FA sign-in errors are a common cause of connection failures, and the usual fix is to sign out and back in — [blog](https://my-blog-muji.pages.dev/en/blog/ipad-mac-sidecar-icloud-2fa-error-signout-en/)
- macOS 27 direct touch keeps the same model: same Apple ID, Wi-Fi and Bluetooth on — [MacRumors 2026-06-09](https://www.macrumors.com/2026/06/09/macos-27-brings-direct-touch-control-to-sidecar/); [Threads summary](https://www.threads.com/@mariusfanu/post/DZYqNHSjYm6/apples-mac-os-golden-gate-and-i-pad-os-add-direct-touch-control-to-sidecar/)

### Inferences
- Sidecar cannot use an iPad that belongs to another person or Apple Account, such as a colleague's or a family member's. A third-party app that pairs over LAN or USB without an account avoids this limit.
- The 10 m figure is a proximity requirement for discovery and connection, not a measured throughput range.

### Gaps
- No source states whether Sidecar works over Wi-Fi infrastructure when AWDL is unavailable, or whether it can work across different networks.
- No source states the exact USB link mode (network over USB or another transport) or its bandwidth.

## 2. Supported Macs and iPads; refresh rate (60 Hz cap?); OS 26/27 changes

### Takeaway
Sidecar requires roughly 2016+ (Skylake+) Macs and Apple Pencil-capable iPads (all iPad Pro, iPad 6th gen+, Air 3rd gen+, mini 5th gen+). Community evidence consistently shows Sidecar is capped at 60 Hz, even on 120 Hz ProMotion iPad Pros. No source shows Apple lifting that cap in macOS 26 or 27. Apple has never published an official refresh-rate figure.

### Cited Findings
- Minimum software: macOS Catalina 10.15+ and iPadOS 13+ — [iDownloadBlog](https://www.idownloadblog.com/2019/10/22/sidecar-system-requirements/)
- Macs: MacBook 2016+, MacBook Air 2018+, MacBook Pro 2016+, Mac mini 2018+, iMac late 2015+, iMac Pro 2017+, Mac Pro 2019, Mac Studio (2022+ / all). One source notes a Skylake or newer CPU requirement, so 2015 MacBook Pros are excluded — [iGeeksBlog](https://igeeksblog.com/?p=597189); [Wccftech](https://wccftech.com/which-mac-and-ipad-models-are-compatible-with-sidecar-list/); [Apple Community (2015 MBP not supported)](https://discussions.apple.com/thread/255965625)
- iPads: iPad Pro (all models), iPad 6th gen+, iPad Air 3rd gen+, iPad mini 5th gen+. These are the Apple Pencil-capable models — [Apple iPad User Guide "Models that support Sidecar" (iPadOS 14)](https://support.apple.com/en-lamr/guide/ipad/aside/ipad42bb5d91/14.0/ipados/14.0); [gori.me](https://gori.me/ipad/ipad-news/121621)
- macOS 27 Golden Gate runs only on Apple silicon (M1+), and macOS 26 Tahoe is the last release for Intel Macs. Intel Macs therefore keep Sidecar only up to macOS 26 — [iThinkDiff](https://www.ithinkdiff.com/macos-27-golden-gate-release-date-compatibility/)
- 60 Hz: Apple Community users with a 2021 12.9" iPad Pro and an M1 iPad Pro report that Sidecar stays at about 60 Hz or below over both USB and wireless — [Apple Community](https://discussions.apple.com/thread/255602183); [MacRumors forum "why limited to 60hz"](https://forums.macrumors.com/threads/ipad-pro-as-second-monitor-through-sidecar-why-limited-to-60hz.2353768)
- There is no setting to view or change the Sidecar refresh rate. This was reported in the macOS 11.1 era — [MacRumors forum](https://forums.macrumors.com/threads/sidecar-ipad-pro-refresh-rate.2281404/)
- July 2026 BetterDisplay discussion: "Apple caps Sidecar to 60hz even on iPads with ProMotion". The only known route to 120 Hz is a BetterDisplay Pro virtual-display trick with a custom 120 Hz mode tied to the iPad, and with it switching Spaces breaks. A commenter argues 60 fps is a streaming-protocol limit — [GitHub BetterDisplay #5609](https://github.com/waydabber/BetterDisplay/discussions/5609)
- iPad Pro ProMotion panel supports 24/30/40/60/120 Hz — [Apple developer docs via iClarified](https://www.iclarified.com/82663/apple-posts-developer-documentation-for-promotion-on-iphone-13-pro-12-refresh-rates-used)
- macOS 26 Tahoe: I found no official Sidecar feature changes. User reports describe regressions: wireless Sidecar broke after upgrading (USB still worked), connections timed out, a timeout bug after using Continuity Camera, and Sidecar plus iPhone Mirroring no longer working at the same time (it worked in Sequoia) — [Apple Community 256143979](https://discussions.apple.com/thread/256143979); [Apple Community 256174168](https://discussions-jp-prz.apple.com/thread/256174168); [Apple Community 256145206](https://discussions.apple.com/thread/256145206); [Apple Community 256159119](https://discussions-jp-prz.apple.com/thread/256159119)
- macOS 27 / iPadOS 27: direct touch added (see section 4). It requires an Apple silicon Mac on macOS 27 plus a compatible iPad on iPadOS 27 — [MacRumors](https://www.macrumors.com/2026/06/09/macos-27-brings-direct-touch-control-to-sidecar/)

### Inferences
- A custom app that delivers 120 Hz on ProMotion iPads would have a concrete, verifiable advantage over Sidecar. The cap appears to be still in place as of July 2026 (macOS 26 era). Whether macOS 27 changed it is unverified (see Gaps).

### Gaps
- No Apple statement on Sidecar refresh rate in any version. No test of the refresh rate on macOS 27 / iPadOS 27 was found.
- No current (2026) Apple list of supported models was retrieved. Lists above come from 2019 to 2024 sources. All iPads released since (M4 iPad Pro, M2/M3 Air, A16 iPad, A17 Pro mini) support Apple Pencil and would presumably qualify, but this was not verified.

## 3. Resolution, scaling, codec, image quality, color, latency

### Takeaway
Sidecar offers macOS scaled-resolution choices for the iPad in Displays settings. It appears to rely on hardware HEVC encode and decode, inferred from user reports where older hardware gives poor quality. No reliable millisecond latency measurement for Sidecar was found. Reviews describe latency only qualitatively as "barely perceivable", and vendor benchmarks (Astropad) leave Sidecar out.

### Cited Findings
- HEVC: users attribute poor Sidecar quality on Macs without HEVC hardware encode (for example older 13" MBP) and iPads without HEVC hardware decode (for example iPad Air 2, A8X) to the lack of HEVC hardware. This is community inference, not Apple documentation (2019 to 2022) — [MacRumors forum "Sidecar - Has anyone got it working?" p.4/p.8](https://forums.macrumors.com/threads/sidecar-has-anyone-got-it-working.2184104/page-8); [GitHub free-sidecar #4](https://github.com/ben-z/free-sidecar/issues/4)
- Scaling: lowering the iPad display resolution improves quality on weak hardware. On an iPad Air 2 the only selectable scaled resolution was 960x704, with artifacts on refresh — [GitHub free-sidecar #4](https://github.com/ben-z/free-sidecar/issues/4)
- Bug: in extended mode Sidecar kept the scaling from an earlier mirroring session instead of the iPad's native resolution, giving a "tiny" desktop (2022) — [Apple Community 253402657](https://discussions.apple.com/thread/253402657)
- Wired Lightning USB is reported slower than USB-C (anecdotal) — [GitHub free-sidecar #4](https://github.com/ben-z/free-sidecar/issues/4)
- Latency, qualitative (2019 beta): "very little response lag, to the point where it's not really perceivable" when used wirelessly. Apple reportedly said there shouldn't be a performance disparity between wired and wireless — [TechCrunch 2019](https://techcrunch.com/2019/06/28/apples-sidecar-just-really-gets-me-you-know/)
- Brad Colbow (artist review, 2019) credited Apple with handling screen latency well, "especially over wifi" — [Brad Colbow review](http://brad.site/reviews/apple-sidecar-review.html)
- Vendor benchmark: Astropad reports Luna Display (LIQUID engine) at 11.32 ms average latency. Sidecar is not in that comparison, and the source is not independent — [Astropad latency comparison](https://astropad.com/blog/comparing-latency-luna-display/)
- User anecdote: Luna has lower latency than Sidecar — [Product Hunt reviews](https://www.producthunt.com/posts/luna-display-2/reviews)
- PetaPixel compared Sidecar, Astropad, Duet and Luna for drawing (2021) — [PetaPixel](https://petapixel.com/2021/06/01/turn-your-ipad-into-a-drawing-tablet-sidecar-vs-astropad-vs-duet-vs-luna/) (content not retrieved)

### Inferences
- Apple does not publish a Sidecar codec, bitrate, chroma format or color space. A custom app that documents these (for example HEVC/H.264, 4:4:4 or 4:2:0, a bitrate value, P3 tagging) and a measured latency would be more transparent than Sidecar.

### Gaps
- No independent, measured Sidecar latency (wired vs wireless) found. Ars Technica, MacRumors and 9to5Mac numbers could not be located or fetched.
- No source on Sidecar color handling (P3 vs sRGB) or chroma subsampling.
- No source confirming that Sidecar defaults to a "looks like" resolution (for example 1366x1024 on 12.9" iPad Pro), though this is commonly assumed. Unverified.

## 4. Apple Pencil, touch, sidebar, Touch Bar, keyboard/trackpad

### Takeaway
Apple Pencil acts as the pointer and click device. Pressure and tilt work only in apps with advanced stylus support, and double-tap (Pencil 2+) can trigger app actions. Hover was reported unsupported (older source). Before macOS 27, fingers could only perform gestures (scroll, pinch, three-finger undo and redo), not click. macOS 27 / iPadOS 27 (Sept 2026) adds direct finger tap and swipe on Apple silicon Macs. A sidebar (left, right or off) and a virtual Touch Bar (top, bottom or off) are provided.

### Cited Findings
- Pressure and tilt for Apple Pencil only in apps with advanced stylus support — [Apple Support 102597 (snippet)](https://support.apple.com/en-us/102597)
- "Enable double tap on Apple Pencil" lets supporting apps perform custom actions on Pencil (2nd gen) or later — [Apple Support 102597](https://support.apple.com/en-us/102597)
- Hover: "there is no hover with the Apple Pencil" (about 2022, may be outdated). No Apple page mentions hover — [MacRumors forum "Everything you wanted to know about using Sidecar"](https://forums.macrumors.com/threads/everything-you-wanted-to-know-about-using-sidecar-on-ipad.2343918/)
- Sidebar can be on the left or right or turned off. Touch Bar can be at the bottom or top or turned off. Touch Bar controls appear for apps with Touch Bar support whether or not the Mac has a Touch Bar — [Apple Support 102597](https://support.apple.com/en-us/102597)
- The sidebar holds commonly used Mac controls (modifier keys, show/hide menu bar and Dock, keyboard, undo), plus Home Screen and Disconnect buttons — [Apple Support 102597](https://support.apple.com/en-us/102597)
- Gestures: three-finger swipe left or double-tap for undo, swipe right for redo, two-finger scroll, pinch-to-zoom — [switchingtomac](https://www.switchingtomac.com/how-to-use-apple-sidecar/); [MacRumors](https://www.macrumors.com/2026/06/09/macos-27-brings-direct-touch-control-to-sidecar/)
- Pre-macOS 27: you had to use the Pencil to click, and finger taps were ignored — [Cult of Mac](https://www.cultofmac.com/news/sidecar-touchscreen-mac-opinion); [Apple Community 251387399](https://discussions.apple.com/thread/251387399); [MacRumors forum M1 iPad Pro](https://forums.macrumors.com/threads/unable-to-use-the-touch-screen-of-m1-ipad-pro-12-9-when-using-sidecar.2384215/)
- macOS 27 / iPadOS 27: users can tap, swipe and interact with macOS apps by finger. Apple Pencil remains supported. It requires an Apple silicon Mac on macOS 27 plus a compatible iPad on iPadOS 27 (announced WWDC June 2026, shipped 2026-09-14) — [MacRumors 2026-06-09](https://www.macrumors.com/2026/06/09/macos-27-brings-direct-touch-control-to-sidecar/); [AppleInsider hands-on 2026-06-10](https://appleinsider.com/articles/26/06/10/hands-on-sidecar-previews-a-full-touch-interface-for-macos-27); [AppleWorld.Today how-to, Sept 2026](https://appleworld.today/2026/09/how-to-use-direct-touch-input-to-sidecar-in-macos-27-and-ipados-27/); [Mac Observer](https://www.macobserver.com/news/macos-27-adds-touch-control-to-sidecar-letting-you-tap-and-use-mac-apps-on-ipad/)
- macOS 27 hands-on (beta) limits: extended display restricted to landscape mode during testing, and small targets such as window traffic-light buttons are hard to hit with a finger — [search summary of macOS 27 hands-on coverage; see AppleInsider](https://appleinsider.com/articles/26/06/10/hands-on-sidecar-previews-a-full-touch-interface-for-macos-27)
- Portrait orientation: AppleInsider has a piece titled "How to use iPad in portrait with Sidecar with macOS Sequoia". Its details were not retrieved, and it may describe a workaround — [AppleInsider Sidecar topic](https://appleinsider.com/topic/sidecar)
- Keyboard/trackpad: the on-screen keyboard is available from the sidebar. A Magic Keyboard or Smart Keyboard attached to the iPad can type into the Mac. This is commonly documented on Apple's page — [Apple Support 102597](https://support.apple.com/en-us/102597) (not directly verified this session; snippet only covered sidebar)

### Inferences
- Before macOS 27, "touch-first" control of Mac apps was a differentiator for third-party apps. As of Sept 2026, Sidecar offers it natively on Apple silicon, but Intel Macs (max macOS 26) still lack it.

### Gaps
- Whether Pencil hover (M2+ iPad Pro, Pencil Pro) or Pencil Pro squeeze and barrel-roll work in Sidecar on macOS 26/27: no source found.
- Whether a trackpad attached to the iPad controls the Mac pointer in Sidecar: not confirmed.
- Whether the macOS 27 landscape-only restriction persisted into the shipping release: unknown.

## 5. Audio, multiple iPads, mirror vs extend, clamshell, app switching

### Takeaway
Audio stays on the Mac and is not sent to the iPad. Only one iPad can be connected at a time. Both mirror and extend are supported. Clamshell behaviour is inconsistent: it is reported to work with an external display attached, while closing the lid otherwise locks or ends the session. Switching to another iPad app suspends the Sidecar session, and it resumes when you return to the Sidecar app.

### Cited Findings
- Audio: "you cannot send audio to the iPad via Sidecar". Audio stays on Mac speakers (Apple Community reply, about 2021) — [Apple Community 253453682](https://discussions.apple.com/thread/253453682)
- Only one iPad at a time. Multiple iPads in range all appear, but only one can connect — [MacStories 2019](https://www.macstories.net/stories/sidecar-in-ios-13-and-macos-catalina-working-seamlessly-between-an-ipad-and-mac/); [Apple iPad User Guide](https://support.apple.com/guide/ipad/use-ipad-as-a-second-display-for-mac-ipad2b1aa3be/13.0/ipados)
- Mirror vs extend: Sidecar works in extended mode or mirroring, chosen in Displays settings — [Apple Community 253402657](https://discussions.apple.com/thread/253402657); [Apple Support 102597](https://support.apple.com/en-us/102597)
- Clamshell, conflicting reports: Astropad says clamshell is not supported by Sidecar (vendor source). A MacRumors user and an Apple Community user report it works when an external monitor is attached, with occasional iPad freezes. MacStories found closing the lid locked the session, which did not resume and needed a reconnect — [Astropad](https://astropad.com/blog/use-your-ipad-as-a-monitor-a-step-by-step-guide-2024/); [MacRumors forum p.13](https://forums.macrumors.com/threads/sidecar-has-anyone-got-it-working.2184104/page-13); [Apple Community 252439547](https://discussions.apple.com/thread/252439547); [MacStories](https://www.macstories.net/stories/sidecar-in-ios-13-and-macos-catalina-working-seamlessly-between-an-ipad-and-mac/)
- App switching: using the App Switcher to go to an iPad app suspends the Sidecar session until you switch back to the Sidecar app, which appears on the Home Screen only while Sidecar is in use — [Apple Support 102597](https://support.apple.com/en-us/102597)
- Disconnect from the Mac: System Settings > Displays > select iPad > Disconnect — [iGeeksBlog](https://www.igeeksblog.com/use-ipad-as-second-display-mac-windows/)

### Inferences
- Because Sidecar is a system feature, it has a special system "Sidecar app" on iPad. It is still suspended when the user switches away, so it is not a picture-in-picture or always-on display while the iPad is used for something else.
- One-iPad-only and no audio are both clear areas where a custom app could differ, for example by supporting multiple iPads or audio forwarding.

### Gaps
- No 2025-2026 confirmation that audio routing or the one-iPad limit is unchanged in macOS 26/27, though nothing suggests a change.

## 6. Known bugs and complaints

### Takeaway
Recurring complaints include wireless connection failures and timeouts (especially after the macOS 26 Tahoe upgrade), poor image quality on older or non-HEVC hardware, scaling glitches, the 60 Hz cap, and the 2FA/account requirement.

### Cited Findings
- Wireless Sidecar stopped working after upgrading to macOS 26 and iPadOS 26, while USB still works — [Apple Community 256143979](https://discussions.apple.com/thread/256143979)
- Repeated "connection timed out" on Tahoe and iPadOS 26 — [Apple Community 256174168](https://discussions-jp-prz.apple.com/thread/256174168)
- Sidecar times out after using Continuity Camera on macOS 26 (user-identified bug) — [Apple Community 256145206](https://discussions.apple.com/thread/256145206)
- Sidecar and iPhone Mirroring can no longer run at the same time on Tahoe — [Apple Community 256159119](https://discussions-jp-prz.apple.com/thread/256159119)
- Third-party troubleshooting guides for macOS 26 Sidecar failures exist, which shows the problem is widespread. These are low-quality SEO sources — [minto.tech](https://minto.tech/macos-26-sidecar-not-connecting-fix/); [macos-tahoe.com](https://macos-tahoe.com/blog/macos-tahoe-continuity-features-complete-troubleshooting-guide-2025/)
- Blurry or poor picture quality and artifacts on older hardware or over wired Lightning — [GitHub free-sidecar #4](https://github.com/ben-z/free-sidecar/issues/4)
- Extended desktop "tiny" due to retained mirror scaling — [Apple Community 253402657](https://discussions.apple.com/thread/253402657)
- Adobe users discuss Sidecar issues with Lightroom Classic — [Adobe Community](https://community.adobe.com/t5/lightroom-classic-discussions/lightroom-classic-and-apple-sidecar/m-p/15322534/highlight/true)

### Gaps
- No data on bug fixes in macOS 26.x point releases or in macOS 27.

## 7. Price; comparison with Universal Control

### Takeaway
Sidecar is free and built into macOS and iPadOS, with no extra hardware. Universal Control is a different feature: it shares one keyboard and mouse across a Mac and iPad that each run their own OS, while Sidecar makes the iPad a display for the Mac.

### Cited Findings
- Sidecar is built into macOS and iPadOS at no extra cost, and competing paid apps position themselves as alternatives — [Duet Display "best alternatives to Apple Sidecar 2025"](https://www.duetdisplay.com/blog/best-alternatives-to-apple-sidecar-for-a-second-monitor-2025-guide); [Parkablogs](https://www.parkablogs.com/content/how-use-tablet-second-monitor)
- Universal Control, like Sidecar, depends on Continuity proximity (Wi-Fi and Bluetooth) and can disconnect when the MacBook lid closes — [Apple Community 255104212](https://discussions.apple.com/thread/255104212)
- On macOS 26, a user reports a Sidecar display appearing when the pointer crosses the edge, and then timing out. This hints at confusion and interplay between Universal Control and Sidecar — [Apple Community 256174168](https://discussions-jp-prz.apple.com/thread/256174168)

### Inferences
- Universal Control (from macOS 12.3 / iPadOS 15.4) shows iPad apps on the iPad and only shares input. It does not extend the Mac desktop, so it is not a display substitute. This is general knowledge and was not sourced this session.

### Gaps
- No primary Apple source retrieved for Universal Control requirements or for the "free" claim. Both are widely known, but Apple's page could not be fetched (support.apple.com is blocked in this session).
