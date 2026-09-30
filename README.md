# 🎵 OneMusic v2

<p align="center">
  <img src="assets/hero/onemusic-engine.gif" width="100%" alt="OneMusic v2" />
</p>

<p align="center">
  <strong>Flutter × Dart × Android × Audio Engine</strong>
</p>

<p align="center">
  🎧 Background Playback &nbsp;•&nbsp;
  ⚡ Headless Audio Pipeline &nbsp;•&nbsp;
  🔒 MediaSession &nbsp;•&nbsp;
  🎛️ Native Controls
</p>

---

## 🎬 Demo

<p align="center">
  <img src="assets/demo/onemusic-preview.gif" width="850" alt="OneMusic Demo" />
</p>

<p align="center">
  <a href="assets/demo/onemusic-demo.mp4">
    ▶️ Watch Full Demo
  </a>
</p>

---

# 🎧 Complete Audio Flow

```mermaid
flowchart LR

    USER["👤 USER"]
    UI["📱 FLUTTER UI"]
    HANDLER["🎧 AUDIO HANDLER"]
    BRIDGE["🌉 HEADLESS BRIDGE"]
    SOURCE["🌐 STREAM SOURCE"]
    BUFFER["📦 BUFFER"]
    PLAYER["⚡ AUDIO ENGINE"]
    OUTPUT["🔊 AUDIO OUTPUT"]

    USER --> UI
    UI --> HANDLER
    HANDLER --> BRIDGE
    BRIDGE --> SOURCE
    SOURCE --> BUFFER
    BUFFER --> PLAYER
    PLAYER --> OUTPUT
```

---

# 🏗️ Complete System Architecture

```mermaid
flowchart TB

    USER["👤 USER"]

    subgraph APP["🎵 ONEMUSIC APP"]
        UI["📱 Flutter UI"]
        HANDLER["🎧 Audio Handler"]
        BRIDGE["🌉 Headless Bridge"]
    end

    subgraph PIPELINE["⚡ AUDIO PIPELINE"]
        SOURCE["🌐 Stream Source"]
        BUFFER["📦 Buffer"]
        PLAYER["🎵 JustAudio Engine"]
    end

    subgraph ANDROID["🤖 ANDROID SYSTEM"]
        SERVICE["⚙️ Foreground Service"]
        SESSION["🎛️ MediaSession"]
        LOCK["🔒 Lockscreen"]
        NOTIFICATION["🔔 Notification"]
    end

    USER --> UI

    UI <--> HANDLER

    HANDLER <--> BRIDGE

    BRIDGE --> SOURCE

    SOURCE --> BUFFER

    BUFFER --> PLAYER

    HANDLER <--> SERVICE

    SERVICE --> SESSION

    SESSION --> LOCK

    SESSION --> NOTIFICATION

    PLAYER --> SERVICE
```

---

# 🔄 Playback Lifecycle

```mermaid
sequenceDiagram

    autonumber

    actor User
    participant UI as 📱 Flutter UI
    participant Bridge as 🌉 Headless Bridge
    participant Handler as 🎧 Audio Handler
    participant Engine as ⚡ Audio Engine
    participant System as 🤖 Android System

    User->>UI: Select Track
    UI->>Bridge: Request Stream
    Bridge->>Bridge: Resolve Source
    Bridge-->>Handler: Return Audio Source

    Handler->>Engine: Load Stream
    Engine->>Engine: Buffer Audio

    Engine-->>Handler: Ready
    Handler->>System: Register MediaSession

    Engine-->>UI: Playing
    System-->>User: 🔔 Notification

    User->>System: Press Pause
    System->>Handler: Pause Event
    Handler->>Engine: Pause
    Engine-->>UI: Paused
```

---

# 🧠 Playback State Machine

```mermaid
stateDiagram-v2

    [*] --> IDLE

    IDLE --> RESOLVING: Play

    RESOLVING --> LOADING: Source Found

    RESOLVING --> ERROR: Failed

    LOADING --> BUFFERING: Connected

    LOADING --> ERROR: Failed

    BUFFERING --> PLAYING: Ready

    BUFFERING --> ERROR: Failed

    PLAYING --> PAUSED: Pause

    PAUSED --> PLAYING: Resume

    PLAYING --> BUFFERING: Buffer Empty

    BUFFERING --> PLAYING: Buffer Ready

    PLAYING --> COMPLETED: Track Finished

    COMPLETED --> IDLE

    ERROR --> RETRY

    RETRY --> RESOLVING

    PAUSED --> IDLE: Stop
```

---

# 🌐 Stream Resolution Flow

```mermaid
flowchart LR

    REQUEST["📱 PLAY REQUEST"]

    METADATA["🔎 METADATA"]

    RESOLVER["🧠 SOURCE RESOLVER"]

    URL["🔗 AUDIO URL"]

    STREAM["🌐 REMOTE STREAM"]

    BUFFER["📦 BUFFER"]

    ENGINE["⚡ AUDIO ENGINE"]

    REQUEST --> METADATA
    METADATA --> RESOLVER
    RESOLVER --> URL
    URL --> STREAM
    STREAM --> BUFFER
    BUFFER --> ENGINE
```

---

# 🔒 Background Playback

```mermaid
flowchart TB

    UI["📱 Flutter UI"]

    HANDLER["🎧 Audio Handler"]

    SERVICE["⚙️ Foreground Service"]

    ENGINE["⚡ Audio Engine"]

    MEDIA["🎛️ MediaSession"]

    LOCK["🔒 Lockscreen"]

    NOTIFICATION["🔔 Notification"]

    AUDIO["🔊 System Audio"]

    UI --> HANDLER

    HANDLER --> SERVICE

    SERVICE --> ENGINE

    ENGINE --> AUDIO

    SERVICE --> MEDIA

    MEDIA --> LOCK

    MEDIA --> NOTIFICATION
```

---

# 🎛️ Media Control Flow

```mermaid
flowchart LR

    USER["👤 USER"]

    LOCK["🔒 LOCKSCREEN"]

    NOTIFICATION["🔔 NOTIFICATION"]

    SESSION["🎛️ MEDIA SESSION"]

    HANDLER["🎧 AUDIO HANDLER"]

    ENGINE["⚡ AUDIO ENGINE"]

    USER --> LOCK
    USER --> NOTIFICATION

    LOCK --> SESSION
    NOTIFICATION --> SESSION

    SESSION --> HANDLER

    HANDLER --> ENGINE

    ENGINE --> SESSION
```

---

# ⚠️ Failure & Recovery Flow

```mermaid
flowchart TD

    START["▶ PLAY"]

    RESOLVE["🔎 RESOLVE SOURCE"]

    CONNECT["🌐 CONNECT"]

    BUFFER["📦 BUFFER"]

    PLAYING["🎵 PLAYING"]

    ERROR["⚠️ ERROR"]

    RETRY["🔄 RETRY"]

    RESET["♻️ RESET"]

    IDLE["⏹ IDLE"]

    START --> RESOLVE

    RESOLVE --> CONNECT

    CONNECT --> BUFFER

    BUFFER --> PLAYING

    RESOLVE -.-> ERROR
    CONNECT -.-> ERROR
    BUFFER -.-> ERROR

    ERROR --> RETRY

    RETRY --> RESOLVE

    ERROR --> RESET

    RESET --> IDLE

    PLAYING --> IDLE
```

---

# 📡 Complete Data Flow

```mermaid
flowchart LR

    A["👤 User Intent"]
    B["📱 Flutter Event"]
    C["🎧 Audio Handler"]
    D["🌉 Headless Bridge"]
    E["🌐 Remote Source"]
    F["📦 Buffer"]
    G["⚡ Audio Engine"]
    H["🎛️ MediaSession"]
    I["🤖 Android"]
    J["🔊 Audio Output"]

    A --> B
    B --> C
    C --> D
    D --> E
    E --> F
    F --> G

    C --> H
    H --> I

    G --> J
    I --> J
```

---

# 🧩 Module Relationship

```mermaid
flowchart TB

    MAIN["main.dart"]

    MAIN --> UI["Flutter UI"]

    MAIN --> HANDLER["audio_handler.dart"]

    HANDLER --> BACKEND["audio_backend.dart"]

    HANDLER --> BRIDGE["yt_headless_bridge.dart"]

    BACKEND --> PLAYER["Audio Engine"]

    BRIDGE --> SOURCE["Stream Source"]

    HANDLER --> MEDIA["MediaSession"]

    MEDIA --> ANDROID["Android Service"]
```

---

# 🚀 OneMusic Pipeline

```mermaid
flowchart LR

    A(("▶ START"))

    B["📱 UI"]

    C["🎧 HANDLER"]

    D["🌉 BRIDGE"]

    E["🌐 SOURCE"]

    F["📦 BUFFER"]

    G["⚡ PLAYER"]

    H["🎛️ MEDIA SESSION"]

    I["🔊 OUTPUT"]

    A --> B
    B --> C
    C --> D
    D --> E
    E --> F
    F --> G
    G --> I

    C --> H
    H --> I
```

---

# 🎬 Visual Architecture

<p align="center">
  <img src="assets/architecture/system-architecture.gif"
       width="100%"
       alt="Animated OneMusic Architecture" />
</p>

<p align="center">
  <img src="assets/architecture/playback-lifecycle.gif"
       width="100%"
       alt="Animated Playback Lifecycle" />
</p>

<p align="center">
  <img src="assets/architecture/data-flow.gif"
       width="100%"
       alt="Animated Data Flow" />
</p>

---

# 📂 Project Structure

```text
onemusic2/
│
├── assets/
│   │
│   ├── hero/
│   │   └── onemusic-engine.gif
│   │
│   ├── demo/
│   │   ├── onemusic-preview.gif
│   │   └── onemusic-demo.mp4
│   │
│   └── architecture/
│       ├── system-architecture.gif
│       ├── playback-lifecycle.gif
│       └── data-flow.gif
│
├── lib/
│   ├── main.dart
│   ├── audio_backend.dart
│   ├── audio_handler.dart
│   └── yt_headless_bridge.dart
│
├── test/
│
├── pubspec.yaml
│
└── README.md
```

---

# 🛠️ Quick Start

```bash
git clone https://github.com/AkshatRaj00/onemusic2.git

cd onemusic2

flutter pub get

flutter analyze

flutter run
```

---

<p align="center">

### 🎵 OneMusic v2

**Flutter → Headless Bridge → Audio Engine → Android → 🔊**

</p>

<p align="center">
  Built for continuous audio.
</p>
