# Feature Priority Matrix for Dioxus Port

## Priority Levels

- **P0 (Critical)**: Must have for MVP
- **P1 (High)**: Important for usability
- **P2 (Medium)**: Nice to have
- **P3 (Low)**: Future consideration

## Feature Matrix

| Feature | Priority | Complexity | Phoenix Dependency | Notes |
|---------|----------|------------|-------------------|-------|
| **Sensor Connectivity** |
| BLE device scanning | P0 | High | None | Platform-specific APIs |
| BLE notifications | P0 | High | None | Core functionality |
| Data decoding | P0 | Medium | None | Port BluetoothUtils |
| Device motion (IMU) | P1 | Medium | None | Platform APIs |
| Geolocation | P1 | Medium | None | Platform APIs |
| Battery monitoring | P2 | Low | None | Platform APIs |
| **Data Pipeline** |
| Local data storage | P0 | Medium | None | SQLite |
| Server WebSocket | P0 | Medium | High | Phoenix Channel protocol |
| Backpressure system | P1 | Medium | High | Client-side batching |
| Data sync queue | P1 | Medium | Medium | Offline support |
| **Visualization** |
| ECG waveform | P0 | High | None | Canvas/wgpu |
| Heart rate display | P0 | Low | None | Simple UI |
| Numeric values | P0 | Low | None | Simple UI |
| Pressure gauge | P1 | Medium | None | SVG/Canvas |
| IMU 3D orientation | P1 | High | None | 3D rendering |
| Maps (geolocation) | P2 | Medium | None | Map tiles |
| Sparklines | P2 | Medium | None | Mini charts |
| **User Interface** |
| Sensor list | P0 | Low | None | Basic UI |
| Sensor detail view | P0 | Medium | None | Core navigation |
| Settings screen | P1 | Low | None | Basic preferences |
| Dark theme | P0 | Low | None | Match existing |
| Responsive layout | P1 | Medium | None | Mobile-first |
| **Room Features** |
| View rooms | P1 | Medium | High | Server sync |
| Join room | P1 | Medium | High | Server interaction |
| Create room | P2 | Medium | High | Server interaction |
| Share sensor to room | P2 | High | High | Complex sync |
| **Communication** |
| View other users' data | P1 | Medium | High | PubSub relay |
| Real-time updates | P1 | High | High | WebSocket |
| **Calls** |
| Voice calls | P3 | Very High | High | WebRTC |
| Video calls | P3 | Very High | High | WebRTC |
| **Offline** |
| Local sensor operation | P0 | Low | None | Core feature |
| Offline data cache | P1 | Medium | None | SQLite |
| Sync when online | P2 | High | Medium | Queue system |
| **Platform** |
| iOS support | P0 | High | None | Primary target |
| Android support | P0 | High | None | Primary target |
| macOS support | P1 | Medium | None | Desktop |
| Windows support | P2 | Medium | None | Desktop |

## MVP Feature Set (P0 Only)

### Core Functionality
1. BLE device scanning and connection
2. Receive notifications from sensors
3. Decode sensor data (heart rate, ECG, pressure, temperature)
4. Store data locally in SQLite
5. Connect to Phoenix server via WebSocket
6. Send measurements to server

### Visualizations
1. ECG waveform (canvas rendering)
2. Heart rate numeric display
3. Basic value displays for all sensor types

### UI
1. Sensor list screen
2. Sensor detail screen
3. Dark theme styling
4. Basic navigation

### Platform
1. iOS build and deployment
2. Android build and deployment

## Complexity Estimates

### Low Complexity (1-2 days)
- Heart rate display
- Numeric value displays
- Settings screen
- Battery monitoring
- Basic navigation

### Medium Complexity (3-5 days)
- Data decoding pipeline
- Local SQLite storage
- WebSocket connection
- Pressure gauge
- Responsive layouts
- Device motion (IMU data)
- Geolocation
- Sparklines

### High Complexity (1-2 weeks)
- BLE scanning/connection (per platform)
- ECG waveform rendering
- IMU 3D visualization
- Server sync with backpressure
- Offline queue system
- Share sensor to room

### Very High Complexity (2-4 weeks)
- WebRTC voice/video calls
- P2P synchronization (Iroh equivalent)
- Cross-platform Bluetooth abstraction

## Recommended Development Order

### Sprint 1: Foundation (2 weeks)
- [ ] Project setup with Dioxus
- [ ] Basic UI shell (navigation, screens)
- [ ] SQLite integration
- [ ] Data models and parsing

### Sprint 2: BLE Core (2 weeks)
- [ ] iOS BLE integration
- [ ] Android BLE integration
- [ ] Device scanning UI
- [ ] Connection management

### Sprint 3: Data Flow (2 weeks)
- [ ] Notification handling
- [ ] Data decoder port
- [ ] Local storage pipeline
- [ ] Basic visualizations

### Sprint 4: Server Integration (2 weeks)
- [ ] WebSocket client
- [ ] Phoenix Channel protocol
- [ ] Send measurements
- [ ] Receive backpressure config

### Sprint 5: Visualizations (2 weeks)
- [ ] ECG waveform
- [ ] Pressure gauge
- [ ] IMU 3D display (basic)
- [ ] Polish and testing

### Sprint 6: MVP Polish (1 week)
- [ ] Bug fixes
- [ ] Performance optimization
- [ ] App store preparation

## Dependencies Between Features

```
BLE Scanning
    └── BLE Notifications
            └── Data Decoding
                    ├── Local Storage
                    │       └── Offline Queue
                    │               └── Server Sync
                    └── Visualizations
                            └── UI Polish

WebSocket Connection
    └── Server Sync
            └── Room Features
                    └── Multi-user Data
                            └── WebRTC Calls
```

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| BLE platform differences | High | High | Create abstraction layer early |
| Performance issues | Medium | High | Profile early, use ring buffers |
| Phoenix protocol changes | Low | Medium | Pin server version, add tests |
| Visualization performance | Medium | Medium | Consider wgpu for heavy rendering |
| App store rejection | Low | High | Follow guidelines, test early |

## Simplification Opportunities

### Features That Can Be Simplified

1. **Backpressure**: Start with simple batching, add adaptive later
2. **Visualizations**: Begin with simple line charts, add 3D later
3. **Offline**: Start with read-only cache, add sync later
4. **Rooms**: Read-only room viewing before full participation

### Features That Can Be Deferred

1. **WebRTC calls**: Complex, consider Phase 2
2. **P2P sync**: Use server relay initially
3. **Advanced visualizations**: Basic first
4. **Multi-sensor correlation**: Single sensor focus first

## Success Metrics for MVP

1. Connect to 3+ BLE sensor types
2. Display real-time data from sensors
3. Store 24+ hours of data locally
4. Sync data to server when online
5. 60 FPS visualization rendering
6. <500ms connection time
7. <10% battery drain per hour (active use)
