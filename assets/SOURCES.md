# Asset sources

Every photo and recording here is NASA work and in the public domain. Nothing comes from the
1995 film. Captions in `data/events.json` say only what the source captions support.

## Photos (`assets/images/`)

| File | NASA ID | What it shows | Source |
|---|---|---|---|
| `crew_portrait.jpg` | S70-36485 | The crew, left to right: Jim Lovell, Jack Swigert, Fred Haise. Official pre-flight portrait, April 1970. | https://images-assets.nasa.gov/image/S70-36485/S70-36485~orig.jpg |
| `face_lovell.jpg`, `face_swigert.jpg`, `face_haise.jpg` | S70-36485 | Each crew member's face, cropped from `crew_portrait.jpg` for the sensor panel and the subtitles: 400 x 500 boxes at x 314, y 716 (Lovell), x 830, y 576 (Swigert) and x 1230, y 910 (Haise), scaled to 240 x 300. | As `crew_portrait.jpg` |
| `moon_far_side.jpg` | AS13-60-8659 | The crater Tsiolkovsky on the lunar far side, photographed by the crew during the pass around the Moon. | https://images-assets.nasa.gov/image/as13-60-8659/as13-60-8659~orig.jpg |
| `co2_adapter.jpg` | AS13-62-8929 | The improvised "mail box" adapter in the Lunar Module that let the crew use the Command Module's lithium hydroxide canisters. NASA's library copy is mirrored (the "SUIT GAS DIVERTER" label reads backwards); this file is flipped back, checked against the LPI scan of the same frame. | https://images-assets.nasa.gov/image/as13-62-8929/as13-62-8929~orig.jpg |
| `aquarius_cabin.jpg` | AS13-62-8990 | Jim Lovell in the Lunar Module cabin. Taken after the mail box photo on the same magazine; no time or temperature is given. Caption from the Apollo Flight Journal photo index. | https://www.lpi.usra.edu/resources/apollo/images/print/AS13/62/8990.jpg (scan: NASA-JSC Image Science and Analysis Laboratory) |
| `service_module.jpg` | AS13-58-8464 | The damaged Service Module after jettison, with the Sector 4 panel blown away. Cropped from the original 4400 x 4600 frame (x 1867, y 2033, 1280 x 720) and scaled to 1920 x 1080. | https://images-assets.nasa.gov/image/as13-58-8464/as13-58-8464~orig.jpg |
| `aquarius_jettison.jpg` | AS13-59-8564 | The Lunar Module Aquarius seen from the Command Module shortly after it was jettisoned. Black and white. | https://www.lpi.usra.edu/resources/apollo/images/print/AS13/59/8564.jpg (scan: NASA-JSC Image Science and Analysis Laboratory) |
| `mission_control_parachutes.jpg` | S70-35471 | Flight controllers in the Mission Operations Control Room just before splashdown, with the parachutes on the main screen. | https://images-assets.nasa.gov/image/S70-35471/S70-35471~orig.jpg |
| `parachutes.jpg` | S70-35638 | The Command Module splashing down under its three main parachutes in the South Pacific. | https://images-assets.nasa.gov/image/S70-35638/S70-35638~orig.jpg |
| `recovery.jpg` | S70-35651 | Jack Swigert lifted toward a recovery helicopter in a net while Jim Lovell waits in the life raft beside the Command Module, with Navy swimmers. 17 April 1970. | https://images-assets.nasa.gov/image/S70-35651/S70-35651~orig.jpg |
| `crew_on_deck.jpg` | S70-35614 | Fred Haise, Jim Lovell and Jack Swigert (left to right) step out of the recovery helicopter onto USS Iwo Jima. Black and white. | https://images-assets.nasa.gov/image/S70-35614/S70-35614~orig.jpg |

## Mission audio (`assets/audio/`)

Mono MP3s, loudness-matched to -16 LUFS, with short fades. Subtitles in `data/events.json` use the
Apollo 13 Flight Journal wording (https://www.apollojournals.org/afj/ap13fj/), timed to each clip and
checked with speech-to-text. "Tape T9xx ch 15" is NASA's Mission Control 30-track recording, CAPCOM
loop, as digitised by NASA JSC on the Internet Archive; GET comes from Apollo in Real Time's tape
alignment and matches the Flight Journal to within 1-2 s.

| File | GET | What is said | Source |
|---|---|---|---|
| `e1_problem.mp3` | 055:55:19 | Swigert: "Okay, Houston, we've had a problem here." Lousma, Lovell ("We've had a Main B Bus Undervolt."), Lousma. | Flight Journal clip https://www.apollojournals.org/afj/ap13fj/audio/a13_0555519.mp3 from 26.39 s (the file starts at about 055:54:52.6, not at its file-name GET) |
| `houston_problem.mp3` | 055:55:35 | Lovell: "Houston, we've had a problem." The intro's cold open: the same line as in `e1_problem.mp3`, cut on its own (41.55-43.80 s of the source, 0.05 s fade in, 0.3 s fade out) and loudness-matched. | Flight Journal clip https://www.apollojournals.org/afj/ap13fj/audio/a13_0555519.mp3 |
| `e1_venting.mp3` | 056:09:07 | Lovell: "...we are venting something out into the - into space." Lousma: "Roger. We copy your venting." Lovell: "It's a gas of some sort." | Flight Journal clip https://www.apollojournals.org/afj/ap13fj/audio/a13_0560317.mp3 from 350.45 s |
| `e2_burn.mp3` | 079:27:52 and 079:32:05 | The PC+2 burn: Lovell "We're burning, 40 per cent." ... "One hundred per cent." ... "Shutdown." CAPCOM Vance Brand answers. Two pieces joined. | Tape T926 ch 15, https://archive.org/download/A13_T926_HR1U_CH7.wav/A13_T926_HR1U_CH15.wav |
| `e3_procedure.mp3` | 090:22:51 | Joe Kerwin starts reading up the CO2 adapter procedure. | Tape T924 ch 15, https://archive.org/download/A13_T924_HR1L_CH7.wav/A13_T924_HR1L_CH15.wav |
| `e3_complete.mp3` | 091:10:17 | Swigert (not Haise): "Okay. Our do-it-yourself lithium hydroxide canister change is complete." at 091:10:26, the first adapter. | Tape T924 ch 15 (as above) |
| `e5_sm.mp3` | 138:04:46 | Lovell: "And there's one whole side of that spacecraft missing." ... "Right by the high gain antenna, the whole panel is blown out, almost from the base to the engine." Kerwin answers. Haise's "Man, that's unbelievable!" is at 138:09:09, so it is not in this clip. | Tape T927 ch 15, https://archive.org/download/A13_T927_HR1U_CH7.wav/A13_T927_HR1U_CH15.wav |
| `e5_farewell.mp3` | 141:30:06 | Kerwin: "Okay, copy that. Farewell, Aquarius, and we thank you." | Tape T927 ch 15 (as above) |
| `e5_splash.mp3` | 142:46:04 to 142:54:48 | First contact after blackout (Kerwin "Odyssey, Houston standing by. Over." / Swigert "Okay, Joe."), "We got two good drogues.", "We show you on the mains, it really looks great.", and the recovery helicopter "Photo 1 observes splashdown at this time." Four pieces joined. | Tape T927 ch 15 (as above) |
