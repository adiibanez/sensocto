# Research-Grade Interpersonal Synchronization Metrics

**Status**: Planned
**Created**: 2026-02-06
**Domain**: Biometric synchronization analysis (HRV, respiration, heartrate)
**Motivation**: Move beyond Kuramoto order parameter to publication-quality synchronization analysis

---

## Context

Sensocto currently computes the **Kuramoto order parameter** in real-time (client-side, in CompositeHRV.svelte and CompositeBreathing.svelte). This is a good starting point but has significant limitations for research:

1. **No statistical significance testing** - No way to distinguish genuine synchronization from chance alignment
2. **Single metric** - Captures only mean-field phase coherence, misses time-lagged, frequency-specific, and nonlinear coupling
3. **No pairwise resolution** - Only global group sync, not who is syncing with whom
4. **No directionality** - Cannot determine leader/follower dynamics

The research literature on interpersonal physiological synchronization (IPS) identifies several complementary metrics, each capturing different coupling mechanisms.

---

## Priority Tiers

### P0: Statistical Significance (Surrogate/Pseudo-Pair Testing)

**Why first**: Without significance testing, ALL synchronization metrics are uninterpretable. A sync value of R=0.7 means nothing if random pairs also produce R=0.65.

**Method**: Generate null distributions by:
- **Phase-shuffled surrogates**: Randomize phase while preserving power spectrum (IAAFT algorithm)
- **Pseudo-pairs**: Compare participants from different sessions who were never actually together
- **Circular time-shift**: Shift one signal by random offset, preserving autocorrelation

**Implementation**: Elixir GenServer + Pythonx (post-hoc, not real-time)

```
Session data → Generate 1000 surrogates → Compute metric on each
→ Build null distribution → p-value = rank of real metric in null distribution
→ Significance: p < 0.05 (Bonferroni-corrected for N*(N-1)/2 pairs)
```

**Where it fits**:
- Post-session analysis (not real-time)
- New module: `Sensocto.Analysis.SurrogateTest`
- Pythonx: `nolds` or custom IAAFT implementation
- Results stored in Postgres, displayed in session report view

**Key references**:
- Schreiber & Schmitz (2000) - Surrogate data for nonlinear time series
- Moulder et al. (2018) - Statistical testing for physiological synchrony

---

### P1: Phase Locking Value (PLV) + Time-Lagged Cross-Correlation (TLCC)

#### PLV (Phase Locking Value)

**What it captures**: Pairwise phase consistency across time, independent of amplitude. More robust than Kuramoto for pairs.

**Formula**: `PLV = |1/T * Σ e^(i(θ₁(t) - θ₂(t)))|`

**Key difference from Kuramoto**: PLV is pairwise (between two signals), Kuramoto is global (all signals). PLV uses the *relative* phase between two specific participants.

**Implementation**:
- **Real-time (Svelte)**: Sliding-window PLV between all pairs, display as NxN heatmap matrix
- **Post-hoc (Pythonx)**: Full-session PLV with significance testing
- Hilbert transform for instantaneous phase extraction (same as Kuramoto)
- Window: 30s sliding, 5s step

**Typical values**: 0 = no coupling, 1 = perfect phase lock. Significant IPS studies report PLV = 0.3-0.6 for coupled dyads.

#### TLCC (Time-Lagged Cross-Correlation)

**What it captures**: Leader-follower dynamics. At what time lag does correlation peak? Who leads?

**Formula**: `TLCC(τ) = corr(x(t), y(t+τ))` for τ ∈ [-10s, +10s]

**Implementation**:
- **Real-time (Svelte)**: Windowed cross-correlation at fixed lag steps (-10s to +10s, 0.5s steps)
- Peak lag indicates leader (+lag = person 1 leads) or follower (-lag = person 2 leads)
- Display: Correlation vs lag plot per pair, or summary "leader board"

**Where both fit**:
- New Svelte component: `CompositeSyncMatrix.svelte` — NxN PLV heatmap + TLCC leader arrows
- Lobby lens: `/lobby/sync` showing pairwise sync matrix
- Real-time feasible for N<20 participants (190 pairs max)

**Key references**:
- Lachaux et al. (1999) - Phase Locking Value original paper
- Codrons et al. (2014) - TLCC for interpersonal coordination
- Palumbo et al. (2017) - PLV for physiological synchrony

---

### P2: Wavelet Transform Coherence (WTC) + Cross-Recurrence (CRQA/MdRQA)

#### WTC (Wavelet Transform Coherence)

**What it captures**: Time-frequency decomposition of synchronization. Shows WHEN and at WHAT FREQUENCY synchronization occurs. Critical for HRV which has distinct frequency bands (LF: 0.04-0.15 Hz sympathetic, HF: 0.15-0.4 Hz parasympathetic).

**Implementation**:
- **Post-hoc only** (computationally expensive)
- Pythonx: `pywt` (PyWavelets) or Morlet wavelet implementation
- Output: 2D time-frequency coherence plot per pair
- Significance: Monte Carlo against phase-shuffled surrogates (from P0)

**Why it matters for HRV**: Two people could sync in HF band (breathing-driven) but not LF band (sympathetic), or vice versa. Kuramoto and PLV collapse these into a single number.

#### CRQA (Cross-Recurrence Quantification Analysis)

**What it captures**: Nonlinear coupling patterns that linear methods (correlation, coherence) miss entirely. Captures shared dynamics in state space.

**Key metrics from CRQA**:
- **%REC** (recurrence rate): Overall coupling strength
- **%DET** (determinism): Predictability of coupling
- **MaxLine**: Longest diagonal line = longest period of sustained coupling
- **Entropy**: Complexity of coupling pattern

**MdRQA** (Multidimensional RQA): Extension for group-level analysis (>2 people). Embeds all N time series in joint state space.

**Implementation**:
- **Post-hoc only** (O(T^2) space complexity for recurrence matrix)
- Pythonx: `pyrqa` library or custom implementation
- Parameters: embedding dimension (m=2-5), time delay (τ from AMI), radius (ε from FNN)
- New module: `Sensocto.Analysis.RecurrenceAnalysis`

**Key references**:
- Zbilut et al. (1998) - CRQA fundamentals
- Wallot et al. (2016) - MdRQA for group synchronization
- Grinsted et al. (2004) - Wavelet coherence

---

### P3: Dynamic Time Warping (DTW) + Interpersonal Recurrence Networks (IRN)

#### DTW (Dynamic Time Warping)

**What it captures**: Shape similarity between time series that may be time-shifted or locally warped. Unlike TLCC which assumes a fixed global lag, DTW allows the lag to vary over time.

**Use case**: Comparing HRV patterns that have similar shapes but non-uniform temporal alignment (e.g., two people relax at slightly different rates).

**Implementation**:
- Pythonx: `dtaidistance` library (C-optimized)
- Output: DTW distance matrix (NxN), warping path visualization
- Can be combined with clustering (hierarchical) to find sync subgroups

#### IRN (Interpersonal Recurrence Networks)

**What it captures**: Network-level synchronization structure. Represents group as a graph where edge weights = CRQA coupling strength between pairs. Enables network analysis (centrality, clustering, community detection).

**Implementation**:
- Build on P2 CRQA results
- Pythonx: `networkx` for graph construction and analysis
- Metrics: Degree centrality (who syncs with most people), betweenness (who bridges subgroups), modularity (sync communities)
- Visualization: Force-directed graph in Svelte (d3-force)

**Key references**:
- Sakoe & Chiba (1978) - DTW original paper
- Wallot et al. (2023) - Interpersonal recurrence networks

---

## Architecture

### Real-Time Pipeline (Svelte, client-side)

```
composite-measurement-event → per-sensor buffer (existing)
                            → Hilbert transform (phase extraction)
                            → Sliding-window metrics:
                                • Kuramoto R (existing)
                                • PLV matrix (P1)
                                • TLCC peak lag (P1)
                            → UI update every 100ms
```

Feasible for N<20 participants with window=30s. All phase-based metrics share the Hilbert transform step.

### Post-Hoc Pipeline (Elixir + Pythonx, server-side)

```
Session complete → AttributeStoreTiered.get_attribute (full history)
                → Sensocto.Analysis.SynchronizationReport.generate(session_id)
                    → SurrogateTest (P0)
                    → PLV + TLCC with significance (P1)
                    → WTC (P2)
                    → CRQA/MdRQA (P2)
                    → DTW distance matrix (P3)
                    → IRN graph metrics (P3)
                → Store results in Postgres (new schema: SyncReport)
                → Display in session review LiveView
```

### New Modules

| Module | Tier | Runtime | Purpose |
|--------|------|---------|---------|
| `Sensocto.Analysis.SurrogateTest` | P0 | Post-hoc | Null distribution generation, significance testing |
| `Sensocto.Analysis.PhaseLockingValue` | P1 | Both | Pairwise PLV computation |
| `Sensocto.Analysis.CrossCorrelation` | P1 | Both | TLCC with lag estimation |
| `Sensocto.Analysis.WaveletCoherence` | P2 | Post-hoc | Time-frequency coherence |
| `Sensocto.Analysis.RecurrenceAnalysis` | P2 | Post-hoc | CRQA + MdRQA |
| `Sensocto.Analysis.DynamicTimeWarping` | P3 | Post-hoc | DTW distance computation |
| `Sensocto.Analysis.RecurrenceNetwork` | P3 | Post-hoc | IRN graph construction |
| `Sensocto.Analysis.SynchronizationReport` | P0+ | Post-hoc | Orchestrates all metrics for a session |

### New Svelte Components

| Component | Tier | Runtime | Purpose |
|-----------|------|---------|---------|
| `CompositeSyncMatrix.svelte` | P1 | Real-time | NxN PLV heatmap with TLCC leader arrows |
| `ANSGaugeCluster.svelte` | P1 | Real-time | Per-person sympathetic/parasympathetic radial gauges |
| `PhaseSpaceOrbit.svelte` | P1 | Real-time | Delay-embedded RMSSD attractor visualization (Canvas) |
| `SyncTopologyGraph.svelte` | P1 | Real-time | Force-directed pairwise sync network (d3-force or Canvas spring sim) |
| `RSAOverlay.svelte` | P1 | Real-time | Breathing-HRV cross-modality coherence (respiratory sinus arrhythmia) |
| `GroupCoherenceWaveform.svelte` | P1 | Real-time | Group mean HRV with confidence bands showing sync envelope |
| `SyncReportView.svelte` | P2 | Post-hoc | WTC spectrograms, CRQA plots, session timeline |
| `RecurrenceNetworkGraph.svelte` | P3 | Post-hoc | Force-directed IRN visualization with centrality metrics |

### Database Schema (Post-Hoc Results)

```sql
CREATE TABLE sync_reports (
  id UUID PRIMARY KEY,
  session_id UUID REFERENCES sessions(id),
  metric_type TEXT NOT NULL,  -- 'plv', 'tlcc', 'wtc', 'crqa', 'dtw', 'irn'
  signal_type TEXT NOT NULL,  -- 'hrv', 'respiration', 'heartrate'
  participant_a TEXT,         -- NULL for group metrics
  participant_b TEXT,         -- NULL for group metrics
  result JSONB NOT NULL,      -- Metric-specific results
  significance JSONB,         -- p-value, null distribution stats
  computed_at TIMESTAMPTZ NOT NULL,
  parameters JSONB            -- Window size, embedding params, etc.
);
```

---

## Visualization Concepts

### Real-Time Visualizations (Client-Side, Svelte)

#### 1. Pairwise Sync Matrix — `CompositeSyncMatrix.svelte` (P1, highest priority)

NxN heatmap where each cell = PLV between two participants. Color intensity = coupling strength (0=black, 1=bright). Animated directional arrows on cells show TLCC lag (who leads whom). Diagonal shows self-sync (always 1.0). Tap a cell to expand the pair's correlation-vs-lag plot.

**Why first**: Transforms the single Kuramoto number into a rich picture of who-syncs-with-whom. Reuses existing Hilbert transform. Feasible real-time for N<20 (190 pairs).

**Implementation**: Canvas-rendered heatmap, 30s sliding window, 5s step. PLV computed from existing phase buffers. TLCC at fixed lag steps (-10s to +10s, 0.5s steps).

#### 2. ANS Gauge Cluster — `ANSGaugeCluster.svelte`

Per-person radial gauge showing the sympathetic/parasympathetic balance as a tug-of-war:
- Left hemisphere (red) = sympathetic dominance (low RMSSD, <20ms)
- Right hemisphere (green) = parasympathetic dominance (high RMSSD, >50ms)
- Needle angle derived from RMSSD mapped to sympathovagal spectrum
- All gauges arranged in a circle, Kuramoto sync value in center
- When people sync, needles visually align — like a cockpit instrument cluster for the group's nervous systems

**Implementation**: SVG or Canvas. Each gauge ~60px. Central sync indicator pulses when R>0.6.

#### 3. Phase Space Orbit — `PhaseSpaceOrbit.svelte`

Delay-embed each person's RMSSD: X = RMSSD(t), Y = RMSSD(t-1). Each person traces a colored orbit. When synchronized, orbits overlap and rotate in the same direction. When desynchronized, orbits diverge into different regions.

**Why cool**: This IS the visual precursor to CRQA (P2) — you're literally seeing recurrence structure before computing it. Trailing opacity creates a glowing orbital effect.

**Implementation**: Canvas with alpha trails. Delay τ=1 sample (5s at 0.2Hz). Configurable embedding delay for advanced users. Low compute — just plot existing buffer with offset.

#### 4. Sync Topology Network — `SyncTopologyGraph.svelte`

Force-directed graph: each person = node, edges = pairwise PLV. Edge thickness = coupling strength, edge color = lag direction (blue=leading, orange=following). Spring physics: nodes attract when PLV is high, repel when low — graph physically clusters synchronized subgroups.

**Why cool**: Simplified real-time version of P3 IRN. Instantly reveals group structure — "Person 3 and Person 7 are a synchronized pair isolated from the rest."

**Implementation**: d3-force or lightweight Canvas spring simulation. Node size = RMSSD (bigger = more relaxed). ~60fps render loop.

#### 5. Breathing-HRV Cross-Modality (RSA) — `RSAOverlay.svelte`

Overlay respiration wave (filled area) and HRV line for each person — showing respiratory sinus arrhythmia in real-time. A coherence indicator shows how tightly HRV tracks breathing for each person.

**Why scientifically valuable**: RSA (the coupling between breathing and heart rate variability) is the direct signature of vagal tone. Two signals we already have, combined into one view that no current component shows.

**Data requirement**: Needs both `respiration` and `hrv` attributes for same sensor. Already present in breathing_study scenario.

#### 6. Group Coherence Waveform — `GroupCoherenceWaveform.svelte`

Instead of showing Kuramoto R as just a number, render the actual group mean HRV signal as a waveform with confidence bands (mean +/- 1 SD across participants). When sync is high, the band is tight. When sync is low, the band fans out.

**Visual metaphor**: Like an EEG grand average — the envelope width IS the synchronization story. Underneath, faded individual traces for context.

**Implementation**: Highcharts arearange series for the band, line series for the mean. Updated every 100ms from existing per-sensor buffers.

### Post-Hoc Visualizations (Server-Side, Pythonx → stored → Svelte render)

#### 7. Wavelet Coherence Spectrogram (P2)

Time-frequency 2D heatmap per pair: X=time, Y=frequency (log scale), color=coherence magnitude. Arrows overlay show phase relationship at each time-frequency point. Cone of influence marks edge effects.

**Critical for HRV**: Separates LF (0.04-0.15 Hz, sympathetic) from HF (0.15-0.4 Hz, parasympathetic) synchronization. Two people might sync breathing-driven HRV (HF) but not stress-driven HRV (LF), or vice versa. Kuramoto and PLV collapse these into a single number — WTC separates them.

**Render**: Precomputed Pythonx → JSONB matrix → Svelte heatmap canvas.

#### 8. Recurrence Plot Gallery (P2)

Cross-recurrence plots are inherently beautiful — they look like abstract art. Diagonal line structures = sustained coupling, dot clusters = intermittent coupling, white space = independence. Rendered as a gallery in session report — one plot per pair, forming a visual "fingerprint" of group coupling dynamics.

**Render**: Pythonx generates recurrence matrices → stored as compressed binary → Svelte Canvas render with configurable threshold slider.

#### 9. Session Sync Timeline (P2)

Horizontal timeline of the entire session:
- Color-coded band: group Kuramoto R over time (green=high sync, red=low)
- Marked events: phase transitions where sync suddenly spikes or drops
- Pairwise "sync arcs" above the timeline: arcs connecting pairs when they lock/unlock
- Annotatable: facilitator can mark what was happening at those moments

**Implementation**: SVG timeline with d3 brushing for zoom. Phase transition detection via Kuramoto R derivative threshold.

### Recommended Build Order for Visualizations

1. **CompositeSyncMatrix** (P1) — highest impact, answers "who syncs with whom"
2. **PhaseSpaceOrbit** (P1) — visually striking, computationally trivial (just delay-embed existing buffer)
3. **GroupCoherenceWaveform** (P1) — simple Highcharts addition, makes sync tangible
4. **SyncTopologyGraph** (P1) — reveals group structure dynamically
5. **RSAOverlay** (P1) — scientifically valuable cross-modality view
6. **ANSGaugeCluster** (P1) — aesthetic "cockpit" feel, good for presentations
7. **WTC Spectrogram** (P2) — requires Pythonx pipeline, most scientifically informative post-hoc
8. **Recurrence Plots** (P2) — beautiful but requires CRQA implementation
9. **Session Timeline** (P2) — synthesis view, needs all other metrics

---

## Python Dependencies (via Pythonx)

| Package | Tier | Purpose |
|---------|------|---------|
| `numpy` | All | Array operations (already installed) |
| `scipy` | P0-P1 | Hilbert transform, surrogate generation, cross-correlation |
| `neurokit2` | P0 | Already installed, ECG/HRV processing |
| `pywt` (PyWavelets) | P2 | Wavelet transform coherence |
| `pyrqa` | P2 | Cross-recurrence quantification |
| `dtaidistance` | P3 | Dynamic time warping (C-optimized) |
| `networkx` | P3 | Graph analysis for IRN |

---

## Implementation Order

1. **P0: Surrogate testing** (~2-3 sessions)
   - IAAFT surrogate generation
   - Circular time-shift surrogates
   - Generic significance test wrapper (works with any metric)
   - Apply to existing Kuramoto R as proof of concept

2. **P1: PLV + TLCC + Real-Time Visualizations** (~5-6 sessions)
   - Pairwise PLV computation (reuse existing Hilbert transform / phase buffers)
   - TLCC with peak lag detection
   - `CompositeSyncMatrix.svelte` — NxN PLV heatmap + TLCC leader arrows
   - `PhaseSpaceOrbit.svelte` — delay-embedded RMSSD attractors (Canvas)
   - `GroupCoherenceWaveform.svelte` — group mean + confidence band
   - `SyncTopologyGraph.svelte` — force-directed pairwise network
   - `RSAOverlay.svelte` — breathing-HRV cross-modality (requires both signals)
   - `ANSGaugeCluster.svelte` — per-person sympathovagal gauges
   - Post-hoc PLV/TLCC with P0 significance testing

3. **P2: WTC + CRQA + Post-Hoc Visualizations** (~4-5 sessions)
   - Wavelet coherence computation (Pythonx)
   - WTC spectrogram visualization (time-frequency heatmap per pair)
   - CRQA with proper parameter selection (AMI, FNN)
   - Recurrence plot gallery (cross-recurrence "fingerprints")
   - MdRQA for group-level analysis
   - Session sync timeline with phase transition detection
   - `SyncReportView.svelte` — session report combining all post-hoc views

4. **P3: DTW + IRN** (~3-4 sessions)
   - DTW distance matrix
   - Hierarchical clustering of sync patterns
   - IRN graph construction from CRQA
   - `RecurrenceNetworkGraph.svelte` — force-directed IRN with centrality metrics
   - Network metrics (degree centrality, betweenness, modularity)

---

## What Makes This Research-Grade

| Requirement | How We Meet It |
|-------------|----------------|
| **Statistical significance** | P0 surrogate testing on every metric |
| **Multiple coupling types** | Linear (PLV, TLCC), nonlinear (CRQA), frequency-resolved (WTC) |
| **Pairwise + group** | PLV/TLCC/CRQA for pairs, Kuramoto/MdRQA/IRN for groups |
| **Directionality** | TLCC lag estimation, Granger causality (optional extension) |
| **Temporal dynamics** | Sliding-window metrics show sync changes over time |
| **Frequency specificity** | WTC decomposes by frequency band (LF/HF for HRV) |
| **Reproducibility** | All parameters stored in database, reports are regenerable |
| **Multi-signal** | Same pipeline for HRV, respiration, heartrate |

---

## References

1. Lachaux, J. P., et al. (1999). Measuring phase synchrony in brain signals. *Human Brain Mapping*, 8(4), 194-208.
2. Schreiber, T., & Schmitz, A. (2000). Surrogate time series. *Physica D*, 142(3-4), 346-382.
3. Grinsted, A., et al. (2004). Application of the cross wavelet transform and wavelet coherence to geophysical time series. *Nonlinear Processes in Geophysics*, 11(5/6), 561-566.
4. Zbilut, J. P., et al. (1998). Detecting deterministic signals in exceptionally noisy environments using cross-recurrence quantification. *Physics Letters A*, 246(1-2), 122-128.
5. Wallot, S., et al. (2016). Multidimensional Recurrence Quantification Analysis (MdRQA) for the analysis of multidimensional time-series. *Frontiers in Psychology*, 7, 1835.
6. Palumbo, R. V., et al. (2017). Interpersonal autonomic physiology: A systematic review of the literature. *Personality and Social Psychology Review*, 21(2), 99-141.
7. Moulder, R. G., et al. (2018). Determining synchrony between behavioral time series. *Observational Methods in Organizational Research*, 235-260.
8. Codrons, E., et al. (2014). Spontaneous interpersonal synchronization during physical fitness exercises. *Human Movement Science*, 34, 1-14.
9. Sakoe, H., & Chiba, S. (1978). Dynamic programming algorithm optimization for spoken word recognition. *IEEE Transactions on Acoustics, Speech, and Signal Processing*, 26(1), 43-49.
10. Wallot, S., et al. (2023). Interpersonal recurrence network analysis. *Methods in Psychology*, 9, 100130.
