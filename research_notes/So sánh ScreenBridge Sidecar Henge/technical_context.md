# Technical context for judging ScreenBridge (custom Mac-to-iPad second-display app)

Research date: 2026-11-15. Note: astropad.com and 9to5mac.com could not be fetched in this session (network allowlist), so their content is known only from search-result summaries. Much of the published latency data is from 2019-2022; it is flagged where it appears.

## 1. End-to-end latency of Sidecar, Duet, Luna, Moonlight and Parsec, and what is achievable at 120 Hz

### Takeaway
No independent, glass-to-glass Sidecar latency measurement turned up. Published numbers are either from vendors (Astropad's Luna at about 11 ms over USB and 22 ms over Wi-Fi, from 2019) or older game-streaming tests (Moonlight at about 18-20 ms). Those numbers come from different methods, and ScreenBridge's 1-2 ms and 7-15 ms figures measure only network round-trip time, so none of them can be compared directly. Of the products checked, only Moonlight is documented as doing 120 fps to an iPad Pro. Sidecar appears to be capped at 60 Hz.

### Cited Findings
- **Luna Display (vendor test, 2019):** Astropad measured an average of 11.3 ms over USB, against 52.9 ms for Air Display and about 95 ms for Duet at 60 FPS. TechCrunch repeated the Luna figure, measured on a 13-inch MacBook Pro and an 11-inch iPad Pro over USB. — [TechCrunch](https://techcrunch.com/?p=1773748); [Astropad latency comparison](https://astropad.com/latency-comparison)
- **Luna and Duet over Wi-Fi (vendor test):** Luna averaged 22.4 ms, Duet about 108 ms and Air Display 131.4 ms. Astropad took 50 samples per app using AnyDesk's latency test page and admitted the quality was rather low and the network conditions poor. — [Astropad blog](https://astropad.com/blog/comparing-latency-luna-display/)
- **Luna, inconsistent vendor range:** Astropad's help article gives about 7-25 ms with an average of about 11.5 ms, which does not match its own blog figures. — [Astropad help](https://help.astropad.com/article/467-luna-display-latency-speeds); [Astropad support](https://support.astropad.com/en/articles/11835410-latency-and-expected-speeds-wifi-vs-wired-connections-explained)
- **Sidecar:** Only anecdotal reports exist. Forum users say wired gives "zero latency" or "fantastic" latency, with no measurement. — [MacRumors thread](https://forums.macrumors.com/threads/lowest-latency-wireless-display-output-to-tv-from-macbook-pro-m5-as-a-desktop-space.2481889/); [Blender bug report about Sidecar pen lag](https://developer.blender.org/T81463)
- **Sidecar refresh rate:** Users report Sidecar is capped at 60 Hz on ProMotion iPad Pros, including an M1 iPad Pro and a 2021 12.9-inch on macOS 14.4 ("stuck at around 60hz and below", USB and wireless). There is no way to see or change the iPad's refresh rate in Sidecar. Apple has published no official statement. — [MacRumors: why limited to 60Hz](https://forums.macrumors.com/threads/ipad-pro-as-second-monitor-through-sidecar-why-limited-to-60hz.2353768); [MacRumors 2021](https://forums.macrumors.com/threads/sidecar-ipad-pro-refresh-rate.2281404/); [Apple Community](https://discussions.apple.com/thread/255602183)
- **Moonlight:** Supports 90 Hz and 120 Hz and was tested in 120 Hz mode on an iPad Pro ProMotion display, with latency around 20 ms and sometimes 18-20 ms. This is older data (around 2022, iPad Pro 10.5"). Steam Remote Play tops out at 60 Hz. — [TechSpot](https://www.techspot.com/article/2198-steam-remote-play-vs-moonlight/)
- **Moonlight with a Mac host:** A 2024 Sunshine issue reports a macOS host stuck at a steady 90 fps where a Windows host gave the full 120 Hz on the same tablet. It may since have been fixed. — [Sunshine issue #2745](https://github.com/LizardByte/Sunshine/issues/2745)
- **Moonlight on newer hardware:** A user reports 4K at 120 fps from a PC to an iPad M4. Another notes that streaming at 120 fps needs a 120 Hz host display or a virtual display (Apollo). — [r/MoonlightStreaming](https://reddit.birdcat.cafe/r/MoonlightStreaming/comments/1k7llyn/how_far_we_have_come_from_a_few_years_ago); [Moonlight](https://moonlight-stream.org/)
- **Parsec with a macOS host:** The launch post says macOS hosting lacks 4:4:4 color and virtual displays. Parsec's 4:4:4 mode is a paid Warp feature for Windows hosts with NVIDIA or Intel hardware. Parsec also says 10-bit color costs latency and bandwidth. — [Parsec macOS hosting](https://parsec.app/blog/macos-hosting-preview-available-now); [Parsec Warp](https://parsec.app/warp); [Parsec color accuracy](https://support.parsec.app/hc/en-us/articles/32381785123860-Improve-Stream-Quality-and-Color-Accuracy)
- **Apple's own High Performance Screen Sharing (Mac to Mac):** Requires Apple silicon on both Macs and macOS Sonoma 14 or later. It offers 4:4:4 chroma, HDR, stereo audio and 30 or 60 fps (not 120), up to 4K per virtual display. Apple recommends a wired connection and at least 75 Mbps for one 4K display. — [Apple support](https://support.apple.com/guide/remote-desktop/apdf8e09f5a9/mac)
- **Duet and Luna at 120 Hz:** No source found that documents 120 Hz support for either. The latest Luna update found is from 2022 (M2 iPad Pro Hover support). — [AppleInsider 2022](https://appleinsider.com/articles/22/11/16/astropad-studio-luna-update-adds-ipad-pro-hover-support-more-gestures)
- **Apple's iPad 120 Hz external-display support:** At the March 2026 Studio Display XDR launch, only the M5 iPad Pro could drive the display at 120 Hz; other iPads were limited to 60 Hz. This is external display output, not Sidecar. — [MacRumors](https://www.macrumors.com/2026/03/03/studio-display-xdr-120hz-limits/)

### Inferences
- Running at 120 Hz with about 100-111 fps delivered is a real differentiator: Sidecar (60 Hz in user reports), Apple Screen Sharing (60 fps maximum) and the vendor-documented Duet and Luna figures are all 60 fps. Moonlight is the only peer documented at 120 fps, and it is a game-streaming client, not a second-display extension.
- ScreenBridge's 1-2 ms cable and 7-15 ms Wi-Fi numbers are network round-trip times. Glass-to-glass latency adds capture, encode, decode and display time. At 120 Hz each frame period is about 8.3 ms, so a realistic glass-to-glass figure is probably in the low tens of milliseconds. ScreenBridge should measure it, for example with a high-speed camera, before claiming parity with Luna's roughly 11 ms (a vendor figure).
- The comparison numbers mix methods (AnyDesk test page, in-app overlays, camera tests) and come from 2019-2022 hardware. The report should present them as indicative only.

### Gaps
- No independent, current measurement of Sidecar, Duet or Luna latency on M-series hardware.
- No confirmed current Duet or Luna refresh-rate maximums; their release notes could not be fetched.
- No 2025-2026 glass-to-glass measurement for Moonlight with a Mac host and an iPad Pro client.

## 2. HEVC 4:2:2 10-bit and 4:4:4 encode on M2 and M2 Pro, and HEVC 4:2:2 decode on the M2 iPad

### Takeaway
HEVC 4:2:2 10-bit hardware encode on Apple silicon is publicly exposed (`kVTProfileLevel_HEVC_Main42210_AutoLevel`) and used by Compressor and Resolve. HEVC and H.264 4:4:4 profiles exist only as undocumented VideoToolbox symbols. Apple publishes no statement on iPad M2 hardware decode of HEVC 4:2:2. The 4:2:2 option is therefore legitimate but carries a compatibility risk on the decode side, and 4:4:4 would mean relying on undocumented APIs.

### Cited Findings
- **Public 4:2:2 profile:** FFmpeg ticket #10127 (2022) links to the public constant `kVTProfileLevel_HEVC_Main42210_AutoLevel`. A 2024 ticket says FFmpeg's `videotoolboxenc` still lacks the profile even though Apple silicon supports 10-bit 4:2:2 encoding. — [FFmpeg #10127](https://trac.ffmpeg.org/ticket/10127); [FFmpeg #11097](https://ffmpeg.org/pipermail/ffmpeg-trac/2024-July/070170.html)
- **Apple and third-party use:** Compressor 4.6.1 added HEVC 10-bit 4:2:2 encoding on Apple silicon Macs with macOS 12.3 or later, and DaVinci Resolve 17.4.4 added Main 4:2:2 10 on Apple silicon (2022). — [Daejeon Chronicles](https://daejeonchronicles.com/2022/02/17/resolve-update-adds-support-for-hevc-main10-final-cut-pro-still-destroys-resolve/)
- **Developer forum confirmation:** A reply in an Apple Developer Forums thread states that Apple silicon supports HEVC 10-bit and 4:2:2. — [Apple Developer Forums 758804](https://developer.apple.com/forums/thread/758804)
- **Undocumented 4:4:4 profiles (July 2026, macOS/Xcode 26.4):** A developer found `kVTProfileLevel_HEVC_Main44410_AutoLevel`, `kVTProfileLevel_HEVC_Main444_AutoLevel` and `kVTProfileLevel_H264_High444Predictive_AutoLevel`. They are returned by `VTSessionCopySupportedPropertyDictionary` but appear only in `VideoToolbox.tbd`, not the public headers. Defining them manually "seems to work". Apple has not replied, and the post does not name the hardware tested. — [Apple Developer Forums 837412](https://developer.apple.com/forums/thread/837412)
- **Apple's own 4:4:4 pipeline:** Apple's High Performance Screen Sharing offers 4:4:4 chroma on Apple silicon, which shows Apple itself does 4:4:4 screen streaming. The codec used is not stated. — [Apple support](https://support.apple.com/guide/remote-desktop/apdf8e09f5a9/mac)
- **Hardware decode on Mac:** Adobe announced hardware decode of 4:2:2 10-bit H.264 and HEVC on Apple silicon Macs. That covers Macs, not iPad. — [Adobe community](https://community.adobe.com/announcements-732/discuss-hardware-acceleration-decode-for-4-2-2-10-bit-h264-hevc-now-available-on-mac-arm-beta-312861)
- **iPad decode:** Apple's older iOS 11 HEVC table lists only 8-bit and 10-bit decode on A9 and later, with no 4:2:2 entry. The only claim found about M2 4:2:2 decode is an unsourced forum post. — [Plex forum](https://forums.plex.tv/t/hevc-and-ios11/213755.md); [Vegas forum](https://www.vegascreativesoftware.info/us/forum/any-graphics-cards-with-hevc-h-265-422-10bit-encoding-decoding--147584)
- **M2 encode errors:** An FFmpeg ticket reports HEVC VideoToolbox encode failing with error -12908 on M2 under Sonoma 14.2.1. — [FFmpeg #10771](https://trac.ffmpeg.org/ticket/10771)

### Inferences
- The M2 iPad Pro has the same media engine generation as the M2 Mac, so hardware 4:2:2 decode is plausible. However, Apple does not document it for iPadOS, so ScreenBridge should query `VTIsHardwareDecodeSupported` or check at runtime and fall back to 4:2:0 HEVC. If decode silently falls back to software, latency and battery use would rise sharply.
- Text-heavy desktop content benefits most from 4:4:4. ScreenBridge's 4:2:2 is a halfway step (full vertical chroma, half horizontal), so colored text edges are still subsampled horizontally.
- Display P3 plus 10-bit is a real quality differentiator versus Duet, Luna and Sidecar, none of which documented anything similar in the sources found.

### Gaps
- No Apple documentation of the M2 media engine's chroma formats for encode or decode on iPadOS.
- No benchmark of encode latency for 4:2:2 versus 4:2:0 on M2 Pro.

## 3. Risks and limits of private CGVirtualDisplay, ScreenCaptureKit prompts in macOS 15 and 26, and Accessibility for event injection

### Takeaway
CGVirtualDisplay is undocumented. No public API creates a virtual display; the only sanctioned alternative is a DriverKit extension that needs an entitlement from Apple. The API is widely used (BetterDisplay, DisplayLink) but can change or crash between macOS versions, and it rules out the Mac App Store. Since macOS 15, ScreenCaptureKit apps get a recurring "Allow For One Month" re-approval prompt that developers cannot avoid, except through the system picker or the VNC-only persistent-capture entitlement. Event injection with CGEventPost needs the Accessibility (post-event) permission.

### Cited Findings
- **No public alternative:** There is no public macOS API to create a virtual display. The public route is a DriverKit extension, which needs an Apple-granted entitlement. — [go-macos/virtualdisplay](https://pkg.go.dev/github.com/go-macos/virtualdisplay)
- **Who uses it, and the stability risk:** BetterDisplay uses the same mechanism. Projects warn that the private API is not supported and may change between macOS versions; DisplayLink and other hardware vendors also use it. — [VirtualDisplayKit](https://gh.r-mj.com/xocialize/VirtualDisplayKit); [jorvik-software note, April 2026](https://jorvik-software.pages.dev/notes/2026/04/11/when-the-stars-align-redux)
- **Crash risk:** One open-source app that uses the API ships a built-in restart mechanism because those APIs "can occasionally crash". — [VoidDisplay](https://gh.r-mj.com/iamsyc/VoidDisplay)
- **Version support:** BetterDisplay v5.x supports macOS 26 Tahoe (26.3 or later) and macOS 27. The v4.x line covers macOS 13.2 through 27. — [BetterDisplay GitHub](https://github.com/waydabber/betterdisplay)
- **Interaction with ScreenCaptureKit:** A developer forum thread reports that ScreenCaptureKit confuses virtual displays. — [Apple Developer Forums 786829](https://developer.apple.com/forums/thread/786829)
- **App Store rule:** Guideline 2.5.1 forbids non-public APIs, and detection is automated by static analysis of symbols in the binary. — [Developer Insider](https://developerinsider.co/appstore-guideline-2-5-1-your-app-uses-public-apis-in-an-unapproved-manner); [ptkd.com](https://ptkd.com/app-store/guidelines/2-5-1)
- **Sequoia's recurring prompt:** macOS 15 asks for screen recording re-approval monthly (weekly in early betas), with an "Allow For One Month" button. It applies to apps using only ScreenCaptureKit, the only way around it is the system content picker, and developers have no workaround. — [9to5Mac](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/); [TidBITS](https://tidbits.com/2024/08/19/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly); [TechRadar](https://techradar.com/computing/mac-os/on-macos-sequoia-youll-only-have-to-deal-with-screen-recording-permission-pop-ups-once-a-month-rather-than-once-a-week)
- **macOS 15.1:** Apple said users would see "fewer dialogs" for apps they use regularly. — [9to5Mac](https://9to5mac.com/2024/10/07/macos-sequoia-screen-recording-popups/)
- **Persistent Content Capture entitlement:** Documented only for VNC apps that need persistent screen capture. — [TidBITS](https://tidbits.com/2024/09/23/how-to-avoid-sequoias-repetitive-screen-recording-permissions-prompts/); [Michael Tsai](https://mjtsai.com/blog/?p=44412)
- **macOS 26:** The Tahoe user guide manages these permissions under "Screen & System Audio Recording". No source confirmed whether the monthly prompt changed in Tahoe. — [Apple Mac User Guide (26)](https://support.apple.com/en-ph/guide/mac-help/control-access-screen-system-audio-recording-mchld6aa7d23/26/mac/26)
- **Accessibility for event injection:** CGEvent.post requires the Accessibility grant (kTCCServicePostEvent). Apple DTS says that grant is limited to posting events. Input Monitoring covers listening only. Apps using CGEvent.post have been rejected under guideline 2.4.5. — [Apple Developer Forums 820594](https://developer.apple.com/forums/thread/820594); [Apple Developer Forums 780626](https://developer.apple.com/forums/thread/780626)
- **Pen pressure through HID:** A developer reports that pressure from a virtual HID digitizer reads as 0. Vendor drivers work because they post tablet events themselves, which suggests CGEvent tablet events, as ScreenBridge uses, are the practical route. This is an unconfirmed developer report. — [Apple Developer Forums 828052](https://developer.apple.com/forums/thread/828052?page=1)
- **Permission revocation:** If Accessibility is revoked while a CGEventTap is active, system input can freeze or the app can hang. — [Apple Developer Forums 844416](https://developer.apple.com/forums/thread/844416); [Apple Developer Forums 735204](https://developer.apple.com/forums/thread/735204)

### Inferences
- Sidecar has none of these burdens because it is a first-party, entitled system service. Duet and Luna avoid the private API through their own drivers: Luna uses a hardware dongle that presents as a real display, and Duet ships its own driver. This is knowledge-based and not verified in this round.
- ScreenBridge's distribution is limited to direct download (Developer ID and notarization still work with private APIs) or source builds. Each major macOS release is a regression risk, so plan a test on each beta, for example macOS 27.
- Users should expect a monthly screen-recording re-consent dialog on macOS 15 and later, plus one-time Accessibility setup. That is friction Sidecar users never see.

### Gaps
- Whether macOS 26 or 27 changed the monthly prompt or CGVirtualDisplay behavior; no Tahoe-specific source was found.
- Whether Duet's current macOS build uses CGVirtualDisplay or a DriverKit extension.

## 4. iPadOS background limits, Picture in Picture with AVSampleBufferDisplayLayer, and free versus paid signing

### Takeaway
iOS 15 and later officially support Picture in Picture from an `AVSampleBufferDisplayLayer` through `AVPictureInPictureController.ContentSource`, and video-call SDKs use it to keep custom-rendered streams alive in the background. That makes ScreenBridge's PiP approach a legitimate public API. With a free Apple ID, though, the app expires every 7 days and is limited to 3 apps per device.

### Cited Findings
- **PiP from a sample-buffer layer:** WWDC21 session 10290 introduced the content source API, which can wrap an `AVPlayerLayer` or an `AVSampleBufferDisplayLayer` and requires `AVPictureInPictureSampleBufferPlaybackDelegate`. — [WWDC21 10290](https://developer.apple.com/wwdc21/10290); [lavanille777 blog](https://lavanille777.github.io/2023/09/01/PIP2.html)
- **Video-call precedent:** Vonage uses an `AVSampleBufferDisplayLayer` with `canStartPictureInPictureAutomaticallyFromInline` for video calls. — [Vonage](https://developer.vonage.com/en/blog/how-to-adopt-ios-picture-in-picture-for-vonage-video-calls)
- **Bugs and platform limits:** Re-entering PiP failed in iOS 15 beta. Apple DTS says the API is iOS-only (not tvOS). A 2026 report describes scaling bugs on macOS. — [Forum 681902](https://developer.apple.com/forums/thread/681902); [Forum 830764](https://developer.apple.com/forums/thread/830764); [Forum 821582](https://developer.apple.com/forums/thread/821582); [Forum 792342](https://developer.apple.com/forums/thread/792342)
- **Free signing limits:** Free provisioning profiles expire after 7 days and require a rebuild. Limits are 3 apps per device, 10 App IDs per 7 days and 3 devices per platform. Paid profiles last up to a year. — [Apple: Choosing a Membership](https://developer.apple.com/support/compare-memberships); [Expo](https://expo.dev/blog/apple-developer-program-explained-free-vs-paid)
- **Early expiry reports:** Some free builds have been reported to expire in 12-24 hours. — [Apple Developer Forums 786762](https://developer.apple.com/forums/thread/786762)

### Inferences
- Without PiP or an audio background mode, iPadOS suspends the app shortly after it is backgrounded and its network socket stops. This is standard iOS behavior and was not re-sourced in this round. PiP is therefore the only sanctioned way to keep the stream visible and alive. Sidecar has no such limit because it is part of the system.
- Using PiP for a desktop stream is arguably outside its intended use (video content). That could matter for App Store review, but it does not matter for sideloading.
- Sideloading is a big usability weakness compared with commercial App Store apps: weekly re-signing, a Mac with Xcode, and the 3-app cap. The paid $99 per year program, a figure not re-verified here, removes the weekly expiry.

### Gaps
- No current Apple documentation was fetched on iPadOS background execution time for network sockets.
- Whether App Review accepts PiP for non-video desktop-streaming apps; no precedent was found.

## 5. Energy and battery impact of streaming at 120 Hz versus 60 Hz

### Takeaway
No measurement isolates 120 Hz versus 60 Hz video streaming or decode on iPad. Phone data shows ProMotion costs little in ordinary use (about 5-6% on the iPhone 15 Pro), but sustained 120 fps content such as gaming costs substantially more. A 120 fps stream is in the gaming category: twice the decode work, plus capture and encode on the Mac.

### Cited Findings
- **iPhone 15 Pro:** Geekbench battery score was 643 at 120 Hz and 675 at 60 Hz (+5%), and the Pro Max improved 6% at 60 Hz. — [PhoneArena](https://www.phonearena.com/news/reducing-iphone-15-pro-refresh-rate-60hz-adds-limited-amount-battery-life_id152661); [Tom's Guide](https://www.tomsguide.com/news/iphone-15-pro-has-a-hidden-60hz-mode-heres-how-much-more-battery-life-you-get)
- **Sustained 120 fps:** ProMotion's impact is negligible in normal use, but 120 fps games "can have a substantial effect" on battery. — [iThinkDifferent](https://www.ithinkdiff.com/iphone-15-pro-battery-life-promotion-120hz/); [Wccftech](https://wccftech.com/promotion-impact-on-iphone-15-pro-battery-life/)
- **Older Android data:** Galaxy S20 Ultra browsing lasted 12 h 23 m at 60 Hz versus 10 h 2 m at 120 Hz. — [PhoneArena](https://www.phonearena.com/news/120Hz-vs-60hz-battery-life-comparison-samsung-galaxy-s20-ultra-plus_id122967)
- **Bandwidth reference:** Apple recommends at least 75 Mbps for one 4K display at 60 fps in High Performance Screen Sharing. — [Apple support](https://support.apple.com/guide/remote-desktop/apdf8e09f5a9/mac)

### Inferences
- At 120 fps, ScreenBridge doubles the frames to capture, encode, encrypt, send and decode per second. Expect higher energy use on both the MacBook and the iPad, plus more Wi-Fi or AWDL radio time. ChaCha20-Poly1305 is cheap on ARM, so encryption adds little.
- Variable frame rate helps: sending frames only when the screen changes lets ProMotion drop its refresh rate on a static desktop. This is the main mitigation and worth checking in ScreenBridge, since ScreenCaptureKit only delivers changed frames.
- A 60 Hz option or adaptive mode should be presented as a battery-saving setting. The report should recommend measuring power, for example with powermetrics on the Mac and the battery drain rate on the iPad, at 60 versus 120 Hz.

### Gaps
- No iPad-specific or streaming-specific 120 Hz versus 60 Hz power measurement was found.
- No published power figures for Sidecar, Duet or Luna.

## 6. Commercial apps with 120 Hz to iPad, and other differentiators

### Takeaway
Among the products checked, only Moonlight (with a Sunshine or Apollo host, mainly on Windows) is documented as streaming 120 fps to an iPad Pro. No evidence was found of 120 Hz in Sidecar, Duet or Luna, and Apple's own Mac-to-Mac High Performance Screen Sharing stops at 60 fps. ScreenBridge's 120 Hz mode, its support for different Apple IDs and its 10-bit P3 path are therefore real differentiators. Its weaknesses are distribution, private APIs and recurring permission prompts.

### Cited Findings
- **Sidecar requirements:** The same Apple Account on both devices, two-factor authentication, devices within 10 meters, and Handoff on. Managed Apple IDs reportedly cannot use Sidecar, though sources conflict. — [Apple support 102597](https://support.apple.com/en-lamr/102597); [Apple Continuity requirements](https://support.apple.com/cs-cz/guide/platform-support/sup60beac13c/web); [OWC blog](https://eshop.macsales.com/blog/86999-how-to-connect-an-ipad-to-macos-sonoma-as-a-wireless-second-display-via-sidecar/)
- **Moonlight 120 Hz:** Supports 90 Hz and 120 Hz on iPad Pro ProMotion. — [TechSpot](https://www.techspot.com/article/2198-steam-remote-play-vs-moonlight/); [Moonlight](https://moonlight-stream.org/)
- **Moonlight with a macOS host:** A Sunshine issue reports a macOS host limited to 90 fps (2024). — [Sunshine #2745](https://github.com/LizardByte/Sunshine/issues/2745)
- **Apple Screen Sharing:** 30 or 60 fps maximum, 4:4:4, Apple silicon on both Macs. — [Apple support](https://support.apple.com/guide/remote-desktop/apdf8e09f5a9/mac)
- **Parsec:** No 4:4:4 or virtual displays on a macOS host. — [Parsec blog](https://parsec.app/blog/macos-hosting-preview-available-now)
- **Luna:** $79.99 hardware dongle. The latest update found is from 2022 (M2 iPad Pro Hover). No 120 Hz specification found. — [AppleInsider](https://appleinsider.com/articles/22/11/16/astropad-studio-luna-update-adds-ipad-pro-hover-support-more-gestures)
- **Duet:** iPad Pro support dates from 2015. No refresh-rate specification found. — [MacRumors 2015](https://www.macrumors.com/2015/12/09/duet-display-ipad-pro-update)

### Inferences
- **Strengths versus Sidecar:** Up to 120 Hz, which Sidecar appears to lack. Works across different Apple IDs, which Sidecar requires to match. Encrypted transport the developer controls. Optional 10-bit P3 color. Up to 2 extra displays (Sidecar supports one iPad per Mac, a knowledge-based claim not verified here).
- **Weaknesses versus Sidecar and commercial apps:** Sideloaded with weekly re-signing. Private CGVirtualDisplay could break on macOS updates. Monthly ScreenCaptureKit re-consent and a one-time Accessibility setup. PiP needed for background. No vendor support and unaudited security, since custom X25519 and ChaCha20 must be implemented correctly: nonce handling and peer authentication matter, and an unauthenticated X25519 exchange is open to man-in-the-middle without pairing verification. Pencil support relies on synthesized tablet events, where Sidecar has native integration.
- **Measured 100-111 fps:** At 120 Hz this means some frames are dropped, about 8-17% of the target, so the report should describe it as roughly 110 fps, not a locked 120.

### Gaps
- Current product pages for Duet (Duet Pro or Air) and Luna 2026 releases could not be checked; astropad.com was unreachable from this session.
- How many iPads Sidecar supports simultaneously was not verified in this round.
