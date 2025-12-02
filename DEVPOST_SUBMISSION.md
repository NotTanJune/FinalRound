# Final Round - AI Interview Coach

## Inspiration

**92% of job seekers experience interview anxiety.** We've all been there, pacing around a room, rehearsing answers to a mirror that offers zero feedback. You nail the content, but did you maintain eye contact? Was your tone confident or shaky? Were you speaking too fast?

The inspiration for Final Round came from a simple realization: the three pillars of interview success, *what you say*, *how you say it*, and *how you present yourself*, are nearly impossible to self-assess. Professional interview coaching costs hundreds of dollars per session. Mock interviews with friends lack objective metrics.

I asked myself: **What if your iPhone could be your personal interview coach?**

With Apple Silicon's Neural Engine capable of 15+ trillion operations per second, ARKit's TrueDepth camera tracking faces at 60 FPS, and Groq's lightning-fast LLM inference, I realized I could build something that wasn't possible just a few years ago, a real-time, AI-powered interview coach that sees you, hears you, and helps you improve.

---

## What it does

Final Round is a comprehensive AI interview preparation platform that provides **real-time, multi-modal feedback** during practice sessions:

### 🎯 Personalized Question Generation
Using **Groq's GPT-OSS 20B model**, Final Round generates interview questions tailored to your target role, experience level, and chosen categories (behavioral, technical, situational). No generic questions, every session is customized to your career goals.

### 👁️ Real-Time Eye Contact Tracking
Leveraging **ARKit and the TrueDepth camera**, Final Round tracks your gaze direction at 30 FPS and displays a live eye contact percentage. Poor eye contact is one of the biggest interview killers, now you can actually measure and improve it.

### 🎙️ Audio Analysis & Transcription
Your spoken responses are captured, transcribed in real-time using **Groq's Whisper API**, and analyzed for:
- Speaking pace (words per minute)
- Pause frequency and duration
- Sentiment and tone
- Content quality and relevance

### 📊 Confidence Scoring
I combine eye contact metrics with tone analysis to generate a **composite confidence score**, a single number that captures your overall presentation quality, not just your answer content.

### 💼 Job Discovery
Based on your profile, Final Round recommends relevant job opportunities with salaries displayed in your local currency, connecting practice directly to opportunity.

---

## How I built it

Final Round is built entirely in **Swift** using **SwiftUI**, designed from the ground up to leverage **Arm architecture** and Apple's specialized hardware accelerators.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        SwiftUI Interface                        │
├─────────────────────────────────────────────────────────────────┤
│  Camera Feed  │  Audio Capture  │  Groq API  │  Supabase Auth   │
├───────────────┼─────────────────┼────────────┼──────────────────┤
│    ARKit      │   AVFoundation  │  URLSession│  Supabase SDK    │
├───────────────┴─────────────────┴────────────┴──────────────────┤
│                    Apple Neural Engine (ANE)                    │
│              Face Detection │ Gaze Estimation │ CoreML          │
└─────────────────────────────────────────────────────────────────┘
```

### Arm Architecture Optimization

**1. Neural Engine for Face Detection**

All face tracking runs on Apple's Neural Engine via the Vision framework, leaving the CPU and GPU free for UI rendering:

```swift
let faceDetectionRequest = VNDetectFaceRectanglesRequest()
// Vision automatically dispatches to Neural Engine
// Result: 8ms inference, 15mW power consumption
```

**2. ARKit TrueDepth Integration**

On devices with TrueDepth cameras, I use ARKit for sub-degree gaze accuracy:

```swift
let lookAtPoint = faceAnchor.lookAtPoint
let isLookingAtCamera = abs(lookAtPoint.x) < 0.1 && abs(lookAtPoint.y) < 0.1
```

**3. Accelerate Framework (NEON SIMD)**

Audio signal processing uses Arm NEON SIMD instructions via the Accelerate framework:

```swift
vDSP_rmsqv(audioBuffer, 1, &rms, frameCount)  // Vectorized RMS calculation
vDSP_meanv(audioBuffer, 1, &mean, frameCount) // SIMD-accelerated mean
```

**4. Groq Integration**

I chose **Groq** for LLM inference because of its exceptional speed, critical for maintaining conversational flow during practice sessions:

- **GPT-OSS 20B**: Question generation and answer evaluation (~200-500ms response time)
- **Llama 4 Scout**: LinkedIn job parsing and extraction
- **Whisper**: Real-time audio transcription

### Performance Benchmarks (iPhone 15 Pro)

| Operation | Latency | Power | Hardware |
|-----------|---------|-------|----------|
| Face detection | 8ms | 15mW | Neural Engine |
| Gaze calculation | 2ms | 5mW | CPU |
| Audio tone analysis | 5ms | 25mW | Accelerate/NEON |
| Sentiment analysis | 12ms | 10mW | CoreML |
| **Total per frame** | **~27ms** | **~55mW** | **Real-time capable** |

### Tech Stack

- **Language:** Swift 5.9
- **UI:** SwiftUI with custom animations
- **Face Tracking:** ARKit + Vision Framework
- **Audio:** AVFoundation + Accelerate
- **AI/LLM:** Groq (GPT-OSS-20B, Llama 3, Whisper)
- **Backend:** Supabase (Auth, PostgreSQL, Storage)
- **Architecture:** MVVM with async/await

---

## Challenges I ran into

### 1. Real-Time Performance Balance

Running face detection, audio analysis, and UI updates simultaneously without frame drops was our biggest challenge. Initial implementations caused thermal throttling after 5 minutes.

**Solution:** I implemented a thermal-aware processing pipeline that reduces face tracking frequency when the device heats up, maintaining smooth performance during long practice sessions.

### 2. Privacy-First Face Processing

Apple's App Store review flagged our TrueDepth usage, requiring detailed documentation of our face data practices.

**Solution:** I architected the system so raw face data *never* leaves the device. Only the calculated eye contact percentage (a simple number) is stored. I updated our privacy policy with explicit face data disclosures.

### 3. Groq API Integration for Real-Time Feedback

Getting Groq's responses fast enough to feel "conversational" required careful prompt engineering and response streaming.

**Solution:** I optimized our prompts for conciseness and implemented streaming responses so feedback appears progressively, reducing perceived latency.

### 4. Graceful Degradation Across Devices

Not all iPhones have TrueDepth cameras. I needed consistent functionality across devices.

**Solution:** The app automatically falls back from ARKit to Vision framework face detection on devices without TrueDepth, ensuring eye contact tracking works on any iPhone with a front camera.

---

## Accomplishments that I am proud of

### 🚀 Production-Ready & App Store Approved
Final Round isn't a hackathon demo, it's a **fully deployed iOS application** available on the App Store. I navigated Apple's review process, including their stringent TrueDepth API documentation requirements.

### ⚡ Sub-30ms Total Processing Latency
True real-time feedback at 30+ FPS, something impossible with cloud-based computer vision solutions.

### 🔒 Privacy-First Architecture
Face data never leaves the device. I proved that powerful AI features and user privacy aren't mutually exclusive.

### 🎨 Polished User Experience
Every interaction has been refined, from the onboarding flow to the session summary analytics. This feels like a production app.

### 📊 Novel Multi-Modal Confidence Scoring
I believe I am the first to combine gaze tracking + tone analysis into a unified "confidence score" for interview preparation.

---

## What I learned

### Arm Architecture Deep Dive
Building Final Round taught us how to truly leverage Apple Silicon:
- **Neural Engine** for ML inference (not just "using CoreML")
- **NEON SIMD** via Accelerate for signal processing
- **Unified Memory** architecture for zero-copy buffer sharing between frameworks

### Groq's Speed Advantage
Groq's inference speed isn't just a nice-to-have, it's **architecturally enabling**. Features that would feel sluggish with 2-3 second API latencies feel instant with Groq's ~200ms responses.

### Privacy as a Feature
Apple's strict review process pushed us to build a better product. Our privacy-first architecture became a selling point, not just a compliance checkbox.

### The Power of Multi-Modal AI
Combining vision (eye contact) + audio (tone) + language (content) creates insights none of these modalities could provide alone. The whole is greater than the sum of its parts.

---

## What's next for Final Round

### 🎭 Expression Analysis
Using ARKit's blendshape coefficients to track facial expressions, are you smiling? Do you look engaged? This adds another dimension to non-verbal feedback.

### 🌐 Cross-Platform Expansion
Bringing Final Round to Android using ML Kit for face tracking, and exploring a web version using MediaPipe.

### 🤝 Mock Interview Mode
Two-way video sessions where users can practice with AI-generated interviewer avatars that respond dynamically to their answers.

### 📈 Longitudinal Analytics
Track improvement over weeks and months, showing users their confidence scores trending upward as they practice.

### 🏢 Enterprise Version
A B2B offering for career services departments, bootcamps, and recruiting firms who want to help their candidates prepare.

---

## Built With

`swift` `swiftui` `arkit` `vision` `coreml` `groq` `llama` `whisper` `supabase` `postgresql` `neural-engine` `accelerate` `arm64` `ios`

---

*Your dream job is one great interview away. Final Round makes sure you're ready.*

