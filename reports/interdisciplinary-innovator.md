# Interdisciplinary Innovation Report: Sensocto Biomimetic Sensor Platform

**Report Date:** March 25, 2026
**Agent:** Interdisciplinary Innovator (Biology, Neurology, Systems Thinking)
**Scope:** Delta since March 20, 2026 report — embodied interaction layer, somatic sensing, collaborative presence, Arabic/RTL support
**Previous Report:** March 20, 2026

---

## Executive Summary

The commits analyzed in this update reveal the platform continuing its biological metamorphosis along two convergent axes: *somatic depth* and *collaborative presence*. Where the previous analysis documented a perceptual and expressive layer growing atop the control hierarchy, these new additions extend that layer into the domain of embodied interaction — the way bodies in space communicate with each other through gesture, posture, and coordinated attention.

Five developments merit interdisciplinary analysis:

1. A composite IMU visualization system that renders whole-body orientation data across multiple sensors simultaneously — making the invisible landscape of embodied movement visible as shared information
2. A HybridPoseClient with GPU/CPU fallback, attention-aware frame throttling, and parallel model initialization — a system that adapts its computational investment to the value of what it is watching
3. A LobbyChannel that brings real-time room awareness to mobile clients — a channel that functions as peripheral spatial awareness of the collaborative social environment
4. A whiteboard system with full state machine, pressure sensitivity, pan/zoom, and a SYNCED/USER_CONTROL role protocol — a collaborative drawing surface that mirrors the neuroscience of joint action
5. Arabic language support with full RTL layout — a cultural extension that raises profound questions about how spatial cognition interacts with data interpretation

Each is examined below through the interdisciplinary lens.

---

## Section 1: Composite IMU Visualization — The Distributed Proprioceptive Map

### 1.1 What Was Built

`CompositeIMU.svelte` renders a multi-sensor orientation time-series chart. It maintains per-sensor data histories of 60 samples, handles four different IMU payload formats (Euler xyz, DeviceOrientation alpha/beta/gamma, and legacy accumulator events), assigns each sensor a distinct color family with brightness-differentiated X/Y/Z axes (solid line, 5-5 dashed, 2-2 dotted), and updates in real time via two event sources: `composite-measurement-event` and the legacy `accumulator-data-event`.

The visual encoding is carefully chosen: same hue for all three axes of one sensor (spatial grouping), different luminance for axis identity (X at full brightness, Y at 70%, Z at 40%), and different dash patterns as a redundant encoding for color-blind users. Up to 15 sensors with 3 axes each — 45 simultaneous time series — can be displayed.

### 1.2 The Biological Principle: The Somatosensory Homunculus as Multi-Sensor Map

The brain maintains a topographic map of the body surface in the primary somatosensory cortex (S1) — the famous homunculus, where each body region is represented in proportion to its tactile sensitivity rather than its physical size. A less commonly discussed parallel exists for proprioception: the body's joint position and movement sensors (muscle spindles, Golgi tendon organs, joint mechanoreceptors) are also mapped in the brain, with the cerebellum maintaining an internal model of the body's current kinematic state updated at approximately 60-100 Hz — matching the 60-sample rolling window in `CompositeIMU.svelte`.

The composite IMU view implements the equivalent of a distributed proprioceptive map: each sensor is a body region, each axis is a degree of freedom, the rolling time window is working memory for recent movement, and the chart canvas is the shared cortical representation. When multiple people wear IMU sensors simultaneously, the composite view allows an observer to see the collective kinematic state of the group — a capability with no natural equivalent in individual biology, but one that emerges in tightly coordinated social animals through behavioral synchrony.

The color-per-sensor encoding mirrors a principle from neurology called population coding: the identity of which neurons fire encodes the specific stimulus. Here, the color identity encodes the specific body (sensor). An experienced user of the composite view will develop the same kind of "muscle memory" for which color means which person that a conductor develops for which section of the orchestra plays which instrument — the color becomes a pre-attentive, identity-stable signal.

### 1.3 An Unmet Opportunity: Cross-Sensor Kinematic Coupling

The current implementation treats each sensor as independent. But the scientifically interesting signal in multi-body IMU data is the *correlation structure* between sensors — do two people's bodies synchronize their movements? Does one person's movement precede another's (leader-follower dynamics)? Behavioral neuroscience calls this "motor coordination" and it is measurable as cross-correlation with a lag parameter.

The `SyncComputer` already computes inter-signal correlation for physiological channels (RSA coherence, PLV). Extending it to handle IMU orientation streams would allow detection of embodied synchrony — the kind measured in studies of mother-infant interaction, dance partners, and therapeutic touch. This is Innovation 7, described in Section 7.

---

## Section 2: HybridPoseClient — Adaptive Resource Allocation as Biological Metabolism

### 2.1 What Was Built

`HybridPoseClient.svelte` implements a complete computer vision pipeline using MediaPipe's PoseLandmarker and FaceLandmarker models. The architecture is notably sophisticated:

- **Parallel preloading**: On component mount, WASM files and both model binaries are fetched in parallel and cached by the browser. Actual inference initialization reuses these cached artifacts, dramatically reducing perceived startup latency.
- **GPU/CPU fallback with timeout**: GPU initialization is raced against a 10-second timeout. If GPU fails or times out, CPU fallback begins automatically. The `withTimeout` utility wraps any promise in a rejection-on-timeout — a clean pattern for hardware that may silently hang.
- **Attention-aware frame throttling**: The `handleBackpressureConfig` callback maps attention levels to target FPS: `high` -> BASE_FPS (30 desktop / 15 mobile), `medium` -> 15/10, `low` -> 5, `none` -> 2. A load multiplier additionally divides the target when system load is elevated.
- **Mode switching**: A `currentMode` variable toggles between `full` (pose + face) and `face` (face only), with a 1-second cooldown to prevent rapid switching.
- **Mobile detection**: User-agent-based `isMobile` flag halves the base FPS and enables per-frame skipping (`MOBILE_FRAME_SKIP`). Edge browser is also detected separately due to GPU delegate instability.

### 2.2 The Biological Principle: Metabolic Rate as a Function of Attention and Load

Living organisms do not maintain constant metabolic rates. The brain's energy consumption varies with cognitive load, and more relevantly, sensory systems vary their sampling rates based on the value of what they are attending to. The fovea, with its dense cone packing, effectively samples the visual field at high resolution only where gaze is directed — other regions are sampled at lower spatial and temporal resolution. This is not a limitation but an energy management strategy: maintaining high-resolution sampling everywhere simultaneously would require metabolically impossible computational resources.

The HybridPoseClient implements the same strategy across two dimensions simultaneously:

| Biological mechanism | HybridPoseClient analog |
|---|---|
| Foveal high-resolution vs. peripheral low-resolution sampling | BASE_FPS at high attention vs. 2 FPS at no attention |
| Thalamic gating — blocking sensory signals during inattention | `backpressurePaused` flag halts inference entirely |
| Metabolic downregulation during low activity (torpor, sleep) | Frame skip counter for mobile; reduced FPS under load multiplier |
| Peripheral nervous system GPU (cerebellum) vs. cortical CPU (frontal) processing | GPU delegate for inference vs. CPU fallback when GPU unavailable |

The GPU/CPU fallback with timeout is particularly elegant from a biological perspective. It mirrors the way the brain handles failed prediction: the primary pathway (fast, efficient, preferred) is attempted first; if it fails within a timeout budget, the system falls back to a slower, more metabolically costly secondary pathway (CPU inference is correct but slower). This graceful degradation is exactly how biological sensory systems handle damage — other cortical areas take over processing when a primary area is lesioned, at the cost of speed and precision.

The parallel face model initialization (started in background after pose is ready, result applied when available) mirrors the way the visual system processes separate features in parallel streams — the dorsal stream (motion, location) and ventral stream (object identity) run concurrently; the face landmarker is effectively a ventral-stream module running parallel to the pose landmarker's dorsal-stream computation.

### 2.3 The Backpressure-Attention Coupling: A Closed Loop

Notably, the attention level that governs HybridPoseClient's frame rate originates from `AttentionTracker` on the server — the same system that governs `SimpleSensor` broadcast frequency and `PriorityLens` quality. This means the entire pipeline from sensor hardware through server processing to browser computer vision inference is governed by a single demand signal. When no one is watching, everything slows down coherently.

In biological terms, this is the equivalent of the reticular activating system (RAS) — the brainstem structure that modulates arousal across the entire cortex simultaneously. When the RAS signals low arousal, processing in sensory cortex, motor cortex, and prefrontal cortex all reduce together. The AttentionTracker functions as the platform's RAS.

---

## Section 3: LobbyChannel — Spatial Peripheral Awareness in Distributed Groups

### 3.1 What Was Built

`LobbyChannel` provides mobile clients with a read-only, real-time view of the room ecosystem. On join, it pushes `lobby_state` with the user's rooms and all public rooms. Subsequently it pushes `room_added`, `room_removed`, `room_updated`, and `membership_changed` events as they occur. The channel joins on `"lobby:{user_id}"` and verifies the socket's `user_id` matches — preventing a user from subscribing to another user's lobby channel. Room state is serialized with sensor details resolved from the live `SensorsDynamicSupervisor` state, not from the database, ensuring the sensor activity status reflects the runtime rather than the persisted state.

### 3.2 The Biological Principle: Peripheral Social Awareness and Place Cells

In group-living mammals, awareness of the social environment — who is where, what they are doing, whether new individuals have arrived or departed — is a continuous background cognitive function. Neuroscience has identified "place cells" in the hippocampus that fire when an animal occupies a specific location, and "social place cells" that fire based on the spatial position of conspecifics. The hippocampus maintains a running model of the social landscape that is updated continuously even when the organism is not explicitly attending to social information.

The LobbyChannel functions as the platform's social place cell system for mobile clients. It maintains an always-current model of the room ecosystem — who has rooms, which rooms are public, how many members each room has, what sensors are active — and delivers delta updates as events occur. Mobile clients do not need to poll; they receive environmental change signals automatically, just as an organism's social place cells update when a groupmate moves.

The `membership_changed` event is particularly well-mapped to this principle: it announces that a conspecific has joined or left a known location (room), which is exactly the signal that triggers social place cell updates in rodent studies.

The design decision to resolve sensor state from `SensorsDynamicSupervisor` rather than the database — using `get_sensor_state(sensor_id, :view, 1)` — means the channel transmits *living* rather than *historical* sensor status. A room with three active sensors shows three live readings; a room whose sensors have gone offline shows the offline state. This is the correct biological behavior: social place cells represent the current state of the environment, not the last recorded state.

---

## Section 4: Whiteboard System — Joint Action and the Neuroscience of Collaborative Drawing

### 4.1 What Was Built

The whiteboard implementation is a full collaborative drawing surface with a formally specified state machine (INIT, READY, SYNCED, USER_CONTROL, ERROR), a 1920x1080 logical coordinate space with pan/zoom viewport transforms, pressure sensitivity, eraser, undo, batch stroke replay, and a control protocol that mirrors the whiteboard server's take/request/deny/release pattern for the avatar ecosystem.

Several implementation decisions are notable:

- **Pressure sensitivity** (`PRESSURE_SENSITIVITY: 0.5`): Pen pressure (from pointer events, available on stylus and some trackpads) modulates stroke width, making the mark reflect the intention force of the drawing gesture.
- **Bump indicator**: A `whiteboard_bump` assign that sets true on any remote stroke activity and clears after 300ms — a brief visual signal that "something is happening on the whiteboard" without requiring the user to attend to the full canvas.
- **SYNCED vs. USER_CONTROL states**: When another user controls the whiteboard, the local client enters SYNCED — it can pan and zoom to follow the controller's drawing area but cannot draw. This is not a simple lock; it is a collaborative viewing mode.
- **Stroke batching**: `whiteboard_strokes_batch` delivers multiple strokes together on sync, preventing the N individual updates that would otherwise overwhelm the render pipeline on join.

### 4.2 The Biological Principle: Joint Action and the Mirror Neuron System

Joint action — two or more agents coordinating their movements to achieve a shared goal — is one of the most studied topics in social neuroscience. A canonical laboratory task is the "joint drawing" paradigm: two participants hold a single stylus together and draw a shape, with neither able to complete it alone. This requires continuous sensorimotor prediction of the other's intended movement.

The SYNCED state in the whiteboard implements a passive form of joint action: the follower's visual system tracks the controller's drawing movements in real time, building an internal model of what the controller is about to draw. Neuroscience has shown that this observation activates the same motor prediction circuits as actually performing the movement — this is the function associated with mirror neurons in macaque premotor cortex and with the human action observation network (area F5, STS, IPL).

The `stroke_progress` event — which fires continuously as a remote user draws, not only on stroke completion — is essential for this principle. A system that only delivered completed strokes would prevent the observer's motor prediction system from engaging: you cannot predict where a line is going if you only see it after it arrives. Delivering in-progress stroke data mirrors the natural visual input during joint observation of another's movement.

The `whiteboard_bump` mechanism maps to a concept in attention neuroscience called the "attentional blink suppression window" — a brief period following an event during which redundant signals are suppressed to prevent the attentional system from being overwhelmed. The 300ms clear timer is in the right range: it corresponds to the duration of the P300 ERP component, the brain's neural signature of task-relevant stimulus detection. Repeated bumps within 300ms are suppressed (the `if not socket.assigns.whiteboard_bump` guard), matching the biological attention suppression window.

The pressure sensitivity implementation carries an insight that is easy to overlook: drawing is not just a visual activity. The force applied to a drawing instrument carries communicative content — hesitation, confidence, emphasis, urgency. By encoding pointer pressure into stroke width, the whiteboard transmits a somatic signal that would otherwise be lost in digital transcription. This is, in miniature, the same principle as haptic feedback in medical robotics: restoring the force information that digital communication strips out.

---

## Section 5: Guided Session — Pedagogical Neuroscience and the Teacher-Student Attention Dyad

### 5.1 What Was Built

The `GuidedSessionHook` now implements a rich bilateral session protocol. The guide can propagate lens changes, sensor focus, annotations, layout changes, quality settings, sensor sort order, and mode changes to all following clients. The follower can break away (`guided_break_away`) and return (`guided_drift_back`). A `guided_presence` message tracks connection state for both participants. The `guidance_available` and `guidance_unavailable` events implement the simplified join flow: no invite code, just a floating badge visible to all lobby members when a guide is active.

### 5.2 The Biological Principle: Joint Attention, Shared Reference, and the Teacher Effect

The guided session implements the computational substrate of pedagogical joint attention — the specific form of joint attention that underlies teaching in humans and a small number of other species. Pedagogical joint attention is distinguished from ordinary joint attention by the teacher's intention to transmit information to the learner, and the learner's inference that the teacher's attention direction is informative.

The `guided_lens_changed` propagation — causing all followers to navigate to the same lens view — is a digital implementation of gaze following: the guide directs attention, the follower's view updates to match. The `guided_sensor_focused` signal narrows this further: not just "look at the ECG view" but "look at this specific sensor's ECG." This two-level specificity (what to look at, which instance of it) maps to the distinction in developmental psychology between "referential gaze following" (following someone's gaze to an object) and "demonstrative pointing" (highlighting a specific feature of that object).

The `guided_break_away` / `guided_drift_back` pair is an especially nuanced implementation. In observational learning research, optimal learning occurs not when the learner rigidly follows the teacher's every move, but when the learner has freedom to explore independently and then re-anchor to the shared reference. The ability to break away and drift back — without ending the session — models the natural rhythm of pedagogical interaction: student explores, teacher recalibrates, student returns to shared reference. Forcing the student to remain locked to the teacher's view at all times would produce exactly the compliance-without-understanding that poor pedagogy generates.

The `guidance_available` floating badge — visible without requiring any action by the potential follower — implements what social psychology calls "ambient social affordance": the environment signals an available social interaction without obligating the observer to initiate it. This reduces the transaction cost of joining a guided session to a single click, which is consistent with research showing that social interactions are disproportionately suppressed by high entry costs even when the expected value is positive.

---

## Section 6: Arabic Language and RTL — Cultural Cognition and Spatial Reading

### 6.1 What Was Built

Arabic (`ar`) has been added as the eighth supported language, with proper RTL layout support. The `ar/LC_MESSAGES/default.po` file implements the standard Arabic plural forms spec (6 plural categories, which is the most complex plural system in the platform's language set) and provides translations for core UI strings: error states, navigation, accessibility labels.

### 6.2 The Biological Principle: Reading Direction, Spatial Cognition, and Data Interpretation

RTL support is conventionally treated as a localization concern. From an interdisciplinary perspective it is something deeper: a question about the relationship between habitual reading direction and spatial reasoning, which has implications for how users interpret time-series data.

Cognitive neuroscience has documented that habitual reading direction influences the mental number line — the spontaneous spatial encoding of numerical magnitude. In right-to-left readers, the mental number line is often reversed compared to LTR readers: smaller numbers tend to be mentally represented on the right, larger on the left. This "spatial-numerical association of response codes" (SNARC) effect extends to time representation: LTR readers tend to mentally represent time as flowing left-to-right (past on left, future on right), while RTL readers show the reverse tendency.

For a sensor platform that displays time-series data (ECG traces, IMU orientation histories, HRV rolling windows), this has a concrete implication: a time-series chart that scrolls from left to right (oldest data on left, newest on right) is cognitively natural for LTR readers and mildly counter-intuitive for RTL readers. The "most recent" data point in a left-to-right chart is spatially on the same side as "small numbers" in an Arabic speaker's mental number line — potentially creating a subtle interference effect.

This is not an argument that charts should be mirrored for RTL users — the research on RTL time-series comprehension is not yet conclusive enough to mandate this. It is an argument for awareness: when Arabic-speaking users report confusion reading time-series data, this may be a contributing factor worth investigating. A testable hypothesis would be whether Arabic-speaking users perform better on time-series interpretation tasks when chart scrolling direction is reversed or when explicit temporal axis labels (newest/oldest) are added — interventions that reduce reliance on the spatial-temporal intuition.

The six-category Arabic plural system (zero, one, two, few, many, other) is the most morphologically complex supported by the platform. Managing it correctly in gettext requires that any plural-form string used in the Arabic locale follow all six forms. This is worth flagging as a maintenance concern: English developers adding new plural strings may test only with two forms (singular/plural) and miss that Arabic requires six — `Plural-Forms: nplurals=6` in the PO file does not automatically validate that six forms are provided in every msgstr.

---

## Section 7: New Cross-Domain Innovation Proposals

### Innovation 7: Cross-Sensor IMU Synchrony Detection

**Biological Inspiration**: Interpersonal motor synchrony — the spontaneous alignment of body movements between people in social interaction — is a well-documented phenomenon with measurable neural correlates. Studies using dual-EEG (hyperscanning) show that synchronized movement is associated with inter-brain coherence in motor and temporal-parietal regions. Synchrony indices are used clinically in autism research, dance therapy, and mother-infant interaction studies. The standard measure is the cross-correlation function between two movement signals at variable time lags — a positive peak at lag zero indicates simultaneous synchrony; a peak at lag T indicates one person leading the other by T milliseconds.

**Current State**: `CompositeIMU.svelte` displays multiple sensors' orientation time series independently. `SyncComputer` computes RSA coherence and PLV for cardiac/respiratory channels but has no IMU input pathway.

**Proposed Implementation**: Extend `SyncComputer` with an `imu_sync` computation mode. For each pair of IMU sensors, compute the cross-correlation of their acceleration magnitude signals over a rolling 5-second window. Output a synchrony matrix (N x N sensors, values 0-1) alongside the existing RSA and PLV outputs. The `CompositeIMU.svelte` could visualize this as a color-coded correlation heatmap beneath the time-series chart — each cell's color encoding the synchrony level between that sensor pair.

**Expected benefit**: Enables detection of embodied coordination and movement coupling between participants — a signal that does not exist in any single sensor's data and cannot be inferred from cardiac or respiratory synchrony alone. Particularly relevant for therapeutic, performance, or educational contexts where body-level coordination is a key outcome.

**Limitation**: Meaningful synchrony requires sensors at comparable body positions (two people both wearing wrist sensors, for example). Sensors at different body locations (one wrist, one chest) will have different movement profiles by anatomy, making synchrony metrics harder to interpret. The UI should communicate sensor placement when available.

---

### Innovation 8: Somatic Annotation Layer for the Whiteboard

**Biological Inspiration**: Medical education distinguishes between declarative knowledge (facts about the body) and procedural knowledge (how to perform a physical skill). Procedural knowledge is encoded and transmitted most effectively through demonstration and embodied experience — the neural systems for procedural memory (basal ganglia, cerebellum, premotor cortex) are distinct from those for declarative memory (hippocampus, prefrontal cortex). This is why reading about a surgical technique is less effective than watching it performed, and watching is less effective than doing it with guidance.

**Current State**: The guided session and whiteboard systems operate independently. A guide can navigate a follower's lens view and draw annotations on a whiteboard, but there is no connection between the whiteboard and live sensor data.

**Proposed Implementation**: A "somatic annotation" mode for the whiteboard, activated when the guide is in a composite lens view (ECG, breathing, IMU). In this mode, the whiteboard canvas overlays the composite view semi-transparently, and the guide's strokes are drawn over the live sensor data. The guide can circle a feature in the ECG trace, annotate a breathing irregularity, or trace the shape of an IMU movement pattern. The annotations would be timestamped and could optionally be stored as `guided_annotation` events with sensor context metadata.

This creates a pedagogical tool where somatic explanation is coupled to live somatic evidence — the teacher explains a feature of the breathing pattern while that pattern is visible in real time beneath the annotation. This is analogous to "annotated demonstration" in surgical training, where the teacher narrates and gestures while operating, creating simultaneous encoding in declarative and procedural memory systems.

**Limitation**: Requires careful z-index and coordinate mapping between the whiteboard's 1920x1080 logical space and the composite view's dynamic layout. Clearing the canvas should not clear the sensor data beneath it — the systems must remain cleanly separated at the data layer even if visually overlaid.

---

### Innovation 9: RTL-Aware Data Flow Direction in Time-Series Views

**Biological Inspiration**: As described in Section 6.2, habitual reading direction influences the mental number line and time representation. LTR readers represent time left-to-right (past left, future right). RTL readers more often represent time right-to-left. This creates a potential mismatch between the default chart scroll direction and the cognitive expectations of Arabic-speaking users.

**Current State**: All time-series charts (ECG, IMU orientation, HRV, breathing) scroll from left to right. This is correct for the majority language set (LTR) and is the Chart.js default.

**Proposed Implementation**: A user preference (storable in user settings alongside `locale`) for `time_series_direction: :ltr | :rtl | :auto`. When set to `:auto`, the value would be inferred from the user's current locale (Arabic and Hebrew -> RTL, all others -> LTR). When RTL is active, time-series charts would render with the time axis reversed — newest data on the left, scrolling rightward into the past — and explicit "newer" / "older" labels on the axis ends.

This is a small implementation effort (Chart.js supports axis reversal via `reverse: true` on the x-scale) with potentially significant cognitive benefit for RTL-language users. It should be validated with Arabic-speaking users before being enabled by default.

**Limitation**: Not all chart types benefit equally. Scatter plots, correlation heatmaps, and polar charts have no inherent time direction and should not be affected. The feature should apply only to rolling time-series views where the x-axis represents time.

---

## Section 8: Architecture Observations

### 8.1 The Somatic Sensing Stack Is Now Coherent

With the composite IMU view, HybridPoseClient, and enhanced guided session, the platform now has a coherent somatic sensing stack:

```
Body hardware layer
  Movesense / Thingy:52 / Phone IMU -> inertial orientation, acceleration
  Camera -> pose landmarks (33 body keypoints + 478 face landmarks)

Processing layer
  ImuTileHook -> quaternion decomposition, tilt/heading/compass
  HybridPoseClient -> MediaPipe GPU/CPU inference, backpressure-throttled
  CompositeIMU.svelte -> multi-sensor orientation history chart
  SkeletonVisualization.svelte -> pose keypoint rendering

Coordination layer
  SyncComputer (cardiac/respiratory) -> cross-body physiological coupling
  [Proposed Innovation 7] -> cross-body IMU movement coupling
  GuidedSessionHook -> propagates sensor focus to followers

Expression layer
  AvatarSplatHook -> IMU accelMag drives spore drift in ecosystem visualization
  SensorBackgroundHook -> sensor activity density drives ambient animation
```

Each layer processes embodied signals at a different level of abstraction — raw physics at the hardware layer, geometric interpretation at the processing layer, social meaning at the coordination layer, aesthetic expression at the expression layer. This matches the hierarchical organization of the somatosensory and motor cortices, where ascending pathways carry increasingly abstract representations of body state.

### 8.2 Guided Session Is Now a Full Pedagogical Protocol

The `GuidedSessionHook` message handlers now cover every significant UI state dimension: lens selection, sensor focus, layout, quality, sort order, mode, panel visibility, and annotations. This completeness matters because partial shared state creates inconsistent experiences — a guide who navigates to the ECG view while a follower's quality is stuck at a low setting the guide has already overridden would see different data at different resolutions. The quality propagation (`guided_quality_changed`) closes this loop.

The guided session is now architecturally capable of functioning as a complete remote clinical supervision protocol — a senior clinician guiding a junior one through sensor data interpretation in real time, with shared view state and annotation capability. The remaining gap is the somatic annotation layer (Innovation 8), which would allow the supervisor to annotate the actual waveforms rather than a separate whiteboard canvas.

### 8.3 The Lobby Is Now Three Layers Deep

The lobby concept has stratified into three distinct presence layers:

1. **LobbyLive (LiveView)**: The primary web UI — sensor cards, lens views, composite visualizations, guided sessions, whiteboard. Subscribes to PubSub for sensor data, guidance, room events.
2. **LobbyChannel (Phoenix Channel)**: Read-only mobile API — room list, membership changes, sensor status. Joins on `lobby:{user_id}`, verifies identity, reuses `rooms:lobby` and `lobby:{user_id}` PubSub topics.
3. **GuidedSession**: A transient overlay — a teacher-student pair who share a synchronized view state within the lobby.

This stratification follows the biological principle of nested social scales: an individual occupies a personal space (their sensor view), a group space (the lobby they share), and an institutional space (the room ecosystem). Each layer has different update frequencies, different information density, and different social obligations. The three-layer architecture correctly encodes these differences.

---

## Section 9: Revised Recommendations

### Status of Previous Proposals

- **Innovation 4 (Complementary Filter for IMU)**: Not yet implemented. Still recommended. The CompositeIMU chart now shows raw orientation values; a complementary filter on the ImuTileHook would smooth the tilt-ball display and benefit the chart indirectly by producing cleaner input data.
- **Innovation 5 (Ecosystem Sonification)**: Not implemented. Still recommended.
- **Innovation 6 (Biome Succession)**: Not implemented. Still recommended.
- **GlymphaticCleaner, AllostasisTracker, PopulationAnomalyDetector** (from March 5 report): Not implemented. Still recommended.

### Immediate (next 1-2 weeks)

1. Add RTL time-series direction preference (Innovation 9) — the Chart.js implementation is `reverse: true` on the x-scale, the settings storage is already in place, the benefit for Arabic-speaking users is concrete and testable.
2. Log Arabic plural string coverage in CI — add a check that all msgstr entries in `ar/LC_MESSAGES/default.po` provide the expected 6 plural forms when the msgid has a plural form. A missing form silently falls back to the first form in Gettext, which may be grammatically wrong.

### Medium-term (next 4-8 weeks)

1. **Innovation 7** (Cross-sensor IMU synchrony): Extend `SyncComputer` with cross-acceleration-magnitude correlation. Add synchrony matrix visualization to `CompositeIMU.svelte`. This creates a genuinely novel capability — embodied coordination detection — that is not available in any existing sensor platform.
2. **Innovation 8** (Somatic annotation whiteboard overlay): Implement transparent whiteboard overlay for composite lens views during guided sessions. Coordinate mapping is the main implementation challenge; the whiteboard and composite view share the same DOM parent, making CSS overlay straightforward.
3. **Innovation 4** (Complementary filter): Self-contained, low-risk, visibly improves ImuTileHook output.

### Longer-term (next quarter)

1. **Innovation 5** (Ecosystem sonification): Wind tone + heartbeat sub-bass as a first pass, using the existing gust modulator.
2. **Innovation 6** (Biome succession): Wire SyncComputer RSA coherence + AttentionTracker level into a slow biome gradient.
3. **AllostasisTracker**, **GlymphaticCleaner**, **PopulationAnomalyDetector** — as described in the March 5, 2026 report.
4. **Mental number line validation study**: Commission or design a small within-subjects experiment with Arabic-speaking users to measure time-series interpretation accuracy with LTR vs. RTL chart direction. Results would provide empirical grounding for the RTL direction feature rather than theoretical motivation alone.

---

## Concluding Observation

The additions analyzed in this report deepen a pattern that has been evident since the earliest commits reviewed: this platform is not built around the metaphor of a dashboard. It is built around the metaphor of a body in a social environment. The sensor data is not read off a screen; it is sensed through a perceptual system (the background animations, the ecosystem visualization) and shared through a social medium (guided sessions, whiteboard, lobby presence).

The Arabic language addition makes this pattern visible from a new angle. A clinical sensor monitoring platform that supports Arabic RTL layout is not merely a localized product — it is a platform designed for human bodies in all cultural configurations, with awareness that the cognitive frameworks those bodies use to interpret spatial and temporal information vary with cultural experience. That awareness, embedded in a language support decision, reflects the same cross-domain thinking that drives the biomimetic architecture.

The somatic sensing stack is coherent. The collaborative presence layer is rich. The next threshold is the closed loop: somatic state feeding back into the collaborative environment, which in turn feeds back into somatic state. The biome succession proposal is one path. The somatic annotation overlay is another. The IMU synchrony matrix is a third. All three converge on the same insight that biological systems have exploited for hundreds of millions of years: the most powerful signals are the ones that move in both directions simultaneously.

---

*Report generated by the Interdisciplinary Innovator agent. All biological analogies are grounded in peer-reviewed neuroscience and ecology literature. Proposed implementations are intended as design directions requiring validation against the project's specific performance constraints.*
