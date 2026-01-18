# SensOcto — Vision & Plan

## The Problem

People are isolated. Technology promised connection and delivered performance.

Current platforms exploit dopamine pathways for profit. Text strips out the body. Video flattens it. We scroll, we perform, we feel more alone. The business model requires us to stay hungry.

## The Vision

**Technology that amplifies empathy instead of exploiting attention.**

A platform where you can *feel* someone's presence — their nervousness, calm, arousal, stress — through real-time physiological data sharing. 

Connection becomes tangible, not performed.

## Core Thesis

**Connection is felt, not performed.**

When you can sense someone's nervousness, you don't have to guess if they're sincere. When you notice a friend's stress rising, you reach out before they ask. When bodies sync, trust forms faster than words allow.

## Why P2P Is Foundational

| Centralized Problem | P2P Solution |
|---------------------|--------------|
| Server costs → monetization pressure | Near-zero marginal cost |
| Data harvesting | Data stays on devices |
| Deplatforming risk | No central authority |
| Surveillance by design | End-to-end encryption native |

P2P isn't a feature. It's the structural foundation that makes non-exploitative technology possible.

## Platform Structure

### SensOcto (non-profit)
Real-time sensor platform for human connection.
- Therapeutic applications
- Disability care
- Research
- General connection

### SensualOcto (commercial)
Intimate/adult vertical on same infrastructure.
- Revenue funds non-profit mission
- Serves communities failed by mainstream platforms

## Core Functionality

### Sensor Parameters
| Input | What It Signals |
|-------|-----------------|
| Heart rate | Arousal level |
| HRV | Stress / relaxation |
| Breathing | Presence, anxiety |
| Movement | Engagement |
| Sync | Connection quality |

### Key Features
1. Real-time physiological presence (1:1 and groups)
2. Ambient visualization (presence as art, not dashboards)
3. Granular permission control
4. Derived states (stress, sync, shift detection)
5. Early warning (pattern changes → trusted contacts)
6. P2P mode (no server required locally)

## Use Cases

- **Therapeutic**: Nervous system visibility in therapy
- **Disability**: Remote wheelchair driving, non-verbal communication, intimacy
- **Mental Health**: Early warning, peer support with presence
- **Intimacy/Kink**: Embodied connection, consent signals, safety
- **Performance**: Audience-performer dynamics visible
- **Groups**: Collective coherence, shared experiences

## Technology Stack

- **Backend**: Elixir 1.19/Phoenix 1.7/Ash 3.0
- **Real-time**: Phoenix Channels, LiveView 1.0
- **P2P**: Iroh (via iroh_ex) - distributed document sync
- **WebRTC**: Membrane RTC Engine for video/voice
- **Sensors**: BLE (Movesense, standard GATT, Thesma, Thorso)
- **Privacy**: End-to-end encryption, no server storage by default
- **Deployment**: Fly.io with hot code upgrades

## Development Phases

| Phase | Scope | Timeline |
|-------|-------|----------|
| MVP | 1:1 sensor sharing, one community | 2-4 weeks |
| Phase 2 | Groups, derived states | 2-3 months |
| Phase 3 | P2P hybrid, mobile | 3-6 months |
| Phase 4 | Full P2P, API, open source | 6-12 months |

## Children's Platform (Future)

Guardian AI that protects without policing:
- Time boundaries built in
- Guides toward offline activity
- Learning moments, not censorship
- Professional loop with mental health advisors

Requires: COPPA/GDPR-K compliance, ethics review, advisory board. Only after adult platform proven.

## Funding Model

- **SensOcto**: Grants, donations (NLnet, Mozilla, Protocol Labs)
- **SensualOcto**: Subscription → funds mission
- No surveillance capitalism

## Open Questions

- Are we building something people actually want, or elegant technology for imaginary users?
- What's the minimum to prove the hypothesis?
- Which community first?

## The Honest Check

The problem was created by technology. Technology-shaped solutions aren't crazy.

But the real test isn't technical elegance — it's whether anyone is bleeding for this.

Find 10 people who say "I need this." Not "sounds cool." Actual pull.

That's the nail test.

---

*Last updated: January 2026*
