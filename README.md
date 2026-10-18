# Funtastic4

A road trip app for travelling together. Everyone in the group sees where the others are on one map, along with each person's ETA to the destination. It uses only Apple frameworks and needs no server of our own.

> **Status:** design stage. The Xcode project is still the blank SwiftUI template; this README records the architecture we agreed on.

## How it works

- Everyone who joins the trip shares their own location and ETA. Anyone can pause sharing.
- Each phone saves its own position and ETA to a shared CloudKit trip zone and reads everyone else's from it.
- Friends join with an invite link sent over WhatsApp or Messages.
- Each phone asks Apple Maps for its own route and ETA. The map draws your route to the destination, and the arrival time Apple Maps returns (14:32) is published so other phones count down on their own.
- Navigate starts turn-by-turn guidance in the app: a banner for the next turn, voice prompts, and a new route if you leave the route. The same menu can still open Google Maps in two-wheeler mode.
- Sharing keeps running with the screen locked or while using other apps.

## System overview

```mermaid
flowchart LR
    you["Your iPhone"]
    friends["Friends' iPhones<br/>(same app)"]
    invite["Invite link<br/>(WhatsApp or Messages)"]
    subgraph apple["Apple services, nothing for us to host"]
        maps["Apple Maps<br/>car route + ETA"]
        ck["CloudKit trip zone<br/>everyone's latest spot + ETA"]
        apns["APNs<br/>change nudge"]
    end
    you -.->|"one-time invite"| invite
    invite -.-> friends
    you <-->|"ETA every ~3 min"| maps
    maps <--> friends
    you <-->|"save + fetch"| ck
    ck <--> friends
    ck --> apns
    apns -.->|"best effort"| friends
```

## Inside the app

The trip engine is the only part we write ourselves, and it runs on every GPS update. Everything around it is an Apple framework.

```mermaid
flowchart TB
    subgraph surfaces["What people see"]
        screen["Map screen<br/>SwiftUI + MapKit"]
        liveAct["Live Activity<br/>ActivityKit + WidgetKit"]
        alertsN["Alerts<br/>UserNotifications"]
        voice["Voice prompts<br/>AVFoundation"]
    end
    subgraph engine["Trip engine (our code)"]
        navigator["Navigator<br/>next turn, voice, reroute"]
        gate["Update gate<br/>≥ 250 m and ≥ 30 s"] --> etaStep["ETA<br/>MapKit arrival time"] --> syncStep["Sync<br/>save mine, fetch all"] --> groupState["Group state<br/>glide pins, sort ETAs"]
    end
    subgraph frameworks["Apple frameworks"]
        coreLoc["Core Location<br/>background GPS"]
        mapKit["MapKit<br/>car route + ETA"]
        cloudKit["CloudKit<br/>shared trip zone"]
    end
    coreLoc --> gate
    coreLoc --> navigator
    navigator --> screen & voice
    navigator -. "reroute" .-> mapKit
    etaStep <--> mapKit
    syncStep <--> cloudKit
    groupState --> screen & liveAct & alertsN
```

## Frameworks

| Framework | What it does here |
|---|---|
| SwiftUI | All screens |
| MapKit for SwiftUI | `Map`, a pin per member (`Annotation`), route line (`MapPolyline`) |
| MapKit | `MKDirections.calculate` returns the route line, its turn-by-turn steps and each rider's ETA in one request; `MKLocalSearch` finds the destination and stops |
| Core Location | `CLLocationUpdate.liveUpdates()` for GPS; `CLBackgroundActivitySession` keeps it running with the screen locked or in other apps; `CLMonitor` detects arrival |
| CloudKit | Trip zone shared with `CKShare`; one record per member; `CKDatabaseSubscription` for change nudges; `encryptedValues` for coordinates |
| ActivityKit + WidgetKit | Live Activity with everyone's ETA on the Lock Screen and Dynamic Island, also shown on CarPlay (iOS 26) and in the Apple Watch Smart Stack |
| AVFoundation | `AVSpeechSynthesizer` speaks the turn prompts through the navigation audio session (ducking music); the `audio` background mode keeps it speaking with the screen locked |
| UserNotifications | Alerts like "Sam arrived" or "Made is 20 min behind", and the "sharing stopped" reminder |

## Core logic

### When a phone sends its position

About once a second while moving, iOS hands the app a GPS reading. The app measures the straight-line distance from the last position it sent (`CLLocation.distance(from:)`) and sends only when both are true:

- the distance is at least 250 m
- at least 30 s have passed since the last send

Readings with an accuracy radius worse than about 50 m are skipped (tunnels, thick trees, indoors). Measuring from the last sent position, instead of adding up small steps, stops GPS wobble while parked from counting as movement. Nothing is sent while parked.

### ETA

MapKit does the whole calculation on Apple's servers; the app doesn't compute routes or ETAs itself. Every ~3 min, or when the rider leaves the route, the app calls `MKDirections.calculate`. The route's polyline is drawn on the map, and `now + expectedTravelTime` is published as the arrival time. Other phones count down from that time, so the figure never goes stale. (`calculate` and `calculateETA` returned the same travel time on test routes, so one request serves both.)

Each phone asks only for its own ETA, so a group of N people makes N requests, not N².

### Between updates

Each update carries speed and heading. Other phones move the pin forward smoothly until the next update arrives.

### Navigation

Navigation runs on the route MapKit already gave us, and looks at every GPS fix (about once a second while moving), not only the ones we publish.

```mermaid
flowchart TB
    fix["GPS fix"] --> locate["Project the fix onto the route line<br/>(meters from the start, meters off the line)"]
    locate --> turn["Next turn = first step end still ahead"]
    turn --> banner["Banner: distance + instruction"]
    turn --> speak{"≤ 400 m or ≤ 80 m away<br/>and not announced yet?"}
    speak -- yes --> voice["Speak it"]
    locate --> off{"> 60 m off the line<br/>for 4 accurate fixes?"}
    off -- yes --> reroute["New MapKit route from here<br/>(at most every 20 s)"]
```

- MapKit steps read "drive this far, then do the instruction", so each instruction belongs at the end of its step's line. Turns and the rider are both measured along the same line, so distances agree.
- Each turn is announced twice, at about 400 m and about 80 m. A turn is identified by its junction, so a refreshed route does not repeat an announcement.
- Leaving the route needs 4 accurate fixes in a row more than 60 m off the line, so a tunnel or tall buildings can't trigger a reroute. A new route is requested at most every 20 s, to stay inside MapKit's request limits.
- Navigation ends when the rider is within 100 m of the destination, even if iCloud can't be reached.
- The screen stays on and the map follows the rider's heading while navigating. The next turn shows at once, using the last known position, even when the rider is standing still.
- Instructions come in the phone's language, and distances in the road units of its region.

### Timing

| What | When |
|---|---|
| GPS | `liveUpdates` while moving; pauses itself when parked |
| Upload + fetch | After ≥ 250 m and ≥ 30 s; nothing while parked |
| Route + ETA | MapKit every ~3 min or when off-route |
| Extra fetches | Every ~15 s while the map is open, plus APNs nudges |
| Live Activity | Updated on the phone after each sync; restarted every 8 h |

## Running in the background

| Situation | What happens |
|---|---|
| Screen locked | Keeps sharing. The background location session keeps GPS running, and the blue location indicator shows it. |
| Using another app (for example, navigating in Google Maps) | Keeps sharing, same as above. |
| Parked | iOS pauses GPS to save battery and resumes it when the phone moves. |
| Navigating, screen locked | Voice prompts keep speaking (the `audio` background mode). The display is only kept on while the app is open. |
| App swiped away (force-quit) | iOS stops the app on purpose and doesn't restart it until the rider opens it again. |

Because a swiped-away app can't keep sharing, we make it visible instead:

- The rider's Live Activity marks itself stale (ActivityKit `staleDate`) and shows "Sharing stopped, open Funtastic4 to resume".
- A reminder notification fires if updates stop while the rider is moving. Each send pushes a scheduled local notification ~5 min into the future, and parking cancels it, so it only goes off when sending stops unexpectedly.
- Friends see "Not updating · last seen 14:05" once the rider's last update is a few minutes old.

Relaunching a swiped-away app through significant-location-change monitoring isn't used. Apple describes that relaunch as off-label, and developers report it no longer relaunches force-quit apps on iOS 26.

## Battery estimates

These are rough estimates, not measurements. They assume a recent iPhone (~13–14 Wh battery), the screen off, decent mobile signal, and ~3–6 J of radio energy per upload. Measure on a real ride with Instruments' Power Profiler (iOS 26 or later) before tuning.

| Option | Uploads per hour (at 40 / 100 km/h) | Estimated drain per hour | 4-hour ride |
|---|---|---|---|
| Upload every 50 m | ~800 / ~2,000 | ~4–8% | ~16–32% |
| Upload every 10–15 s | 240–360 | ~3–7% | ~12–28% |
| **≥ 250 m and ≥ 30 s (chosen)** | ~120 / ~120 | **~2–4%** | **~8–16%** |
| Parked (any option) | 0 | under 0.5% | — |
| Map open on screen | — | +10–20% | — |
| Navigating, in Google Maps or our own screen | — | ~10–20% | ~40–80% |

Where the energy goes:

- **GPS while moving:** ~1–3% per hour. If the rider is already navigating, GPS is on anyway, so our app adds almost nothing here.
- **Mobile radio:** each upload keeps the radio powered for several seconds afterwards. Uploads less than ~10–15 s apart keep it on permanently, which is why the number of uploads matters more than their size.
- **ETA requests, Live Activity updates and the update gate:** well under 1% per hour together.
- **Screen:** by far the biggest cost. An open map or navigation screen outweighs everything above.

## Data (CloudKit)

```mermaid
flowchart LR
    host["Host's iPhone"]
    friend["Each friend's iPhone"]
    subgraph container["CloudKit container"]
        subgraph privDB["Host's private database"]
            subgraph zone["Trip zone"]
                trip["Trip"]
                mHost["Member: host"]
                mA["Member: friend A"]
                mB["Member: friend B"]
            end
        end
        subgraph sharedDB["Friend's shared database"]
            ref["Host's trip zone<br/>(same records, via share link)"]
        end
    end
    host <--> zone
    friend <--> ref
    ref -.-> zone
```

| Record | One per | Fields |
|---|---|---|
| `Trip` | group | name, destination, stops |
| `Member` | person | name, avatar, location (encrypted), speed, heading, arrival time, last update, status (moving / stopped / paused / arrived) |

A trip, step by step:

1. The host taps New trip. The app creates the trip zone, the `Trip` record, the host's `Member` record and a share link.
2. The host sends the link on WhatsApp. A friend taps it, and the app accepts the share.
3. Each phone saves only its own `Member` record, overwriting it each time, so no two phones edit the same record.
4. To see the others, the app fetches only what changed in the zone since its last check.
5. When the trip ends, the host deletes the zone and everyone's data is gone.

## Known limits

- iPhone only, and everyone needs an iCloud account.
- Positions refresh every ~30–45 s while moving, not live; pins glide in between.
- A parked phone stops refreshing in the background until it moves or the app is opened.
- A swiped-away app stops sharing until it's reopened (see [Running in the background](#running-in-the-background)).
- MapKit has no motorcycle mode, so motorbike ETAs use car routes.
- How much live traffic MapKit's ETAs include depends on Apple's coverage in each country.
- Live Activities end after 8 hours.
- Navigation uses MapKit's car routes: no lane guidance, speed limits or incident warnings, and traffic only enters through route refreshes (every ~3 min, or after a reroute).
- Navigation keeps the display on, which is the biggest battery cost (see Battery estimates).

## Open decisions

- **Map provider:** Apple for now; see the comparison below.
- **Friends on the navigation screen:** their routes and ETAs next to yours.
- **Motorbike ETA adjustment:** only if MapKit's car ETAs prove consistently off in testing.
- **Minimum iOS version:** 26.5 now (the Xcode default); the frameworks above work back to iOS 18.
- **Spoken updates** through helmet intercoms (AVFoundation): left out for now.

### Map provider: Apple vs open source vs Google

| | Apple MapKit (current) | Open source (OpenStreetMap) | Google (paid) |
|---|---|---|---|
| Map display | MapKit | MapLibre with OSM map tiles from a tile host | Google Maps SDK |
| Place search | `MKLocalSearch` | Open search services (Nominatim, Photon) | Places API |
| Motorbike routes | No, car routes only | Yes: Valhalla `motorcycle` and `motor_scooter` modes | Yes: two-wheeler mode (beta) |
| Turn-by-turn | Built into this app on MapKit's steps (car routes only) | Ferrostar, an open-source navigation kit | Navigation SDK, or hand off to the Google Maps app |
| Traffic in ETAs | Yes: normal traffic for the time of day, and apparently current conditions | None; OSM records roads, not how busy they are | Yes |
| Cost and hosting | Free, no server | Tile and routing host: free tiers for testing, paid or our own server for real use | Pay per request |
| All Apple | Yes | No | No |

On a 30 km test route:

| Route | Distance | ETA leaving Mon 17:30 / 3 am |
|---|---|---|
| Apple MapKit, car | 29.9 km | 79 / 49 min |
| OSM + Valhalla, car | 31.0 km | 60 / 60 min |
| OSM + Valhalla, motor scooter | 30.4 km, on smaller roads | 63 min, time of day not considered |

Mixing providers isn't an option. Apple's developer agreement (Attachment 6, §2.4) only allows Apple's map data, which includes traffic data, to be displayed on an Apple map, so an open-source map can't show MapKit ETAs. Read strictly, showing Apple ETAs in the Live Activity, which has no map, is a gray area as well.

Current choice: stay with Apple, because traffic-aware ETAs matter more for this app than motorbike-specific routes; in the test, the car and motorbike routes were about the same length. Revisit if offline maps or motorbike-only roads become important.

## Project setup

- Xcode 26.6, SwiftUI app template
- Bundle ID `com.hardy.Funtastic4`
- Minimum iOS 26.5

## License

MIT, see [LICENSE](LICENSE).
