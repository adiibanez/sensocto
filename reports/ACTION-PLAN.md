# Sensocto Action Plan

**Generated:** January 12, 2026 | **Updated:** February 15, 2026
**Based on:** Security, Resilience, Testing, and Accessibility Agent Reports

---

## Priority 1: Critical (Immediate)

### Security Fixes

- [ ] **S-001**: Move hardcoded DB credentials to environment variables (`config/dev.exs`)
- [ ] **S-002**: Move hardcoded secret keys to environment variables (`config/dev.exs`)
- [x] **S-003**: ~~Move Neo4j credentials to environment variables~~ (Neo4j removed from project)
- [ ] **S-004**: Enable WebSocket `check_origin` in production (`config/prod.exs`)

### Resilience Fixes

- [ ] **R-001**: Add `Task.Supervisor` to supervision tree (`lib/sensocto/application.ex`)
- [ ] **R-002**: Replace `Task.start/1` with `Task.Supervisor.start_child/2` in RoomStore

---

## Priority 2: High

### Security Fixes

- [ ] **S-005**: Sanitize RequestLogger plug to filter sensitive data
- [ ] **S-006**: Add security headers (CSP, X-Frame-Options, etc.) to endpoint

### Resilience Fixes

- [x] **R-003**: Replace `IO.puts` with `Logger` across codebase
- [x] **R-004**: Add explicit timeouts to GenServer calls

---

## Priority 3: Medium

### Security Fixes

- [ ] **S-007**: Reduce token lifetime from 365 days to 30 days

### Testing & Accessibility

- [ ] **T-001**: Add comprehensive LiveView test coverage
- [ ] **A-001**: Fix critical WCAG violations in forms and modals

---

## Implementation Status

| ID | Status | Description |
|----|--------|-------------|
| S-001 | DONE | Move DB credentials to env vars |
| S-002 | DONE | Move secret keys to env vars |
| S-003 | N/A | ~~Move Neo4j credentials~~ (Neo4j removed from project) |
| S-004 | DONE | Enable WebSocket origin checking |
| S-005 | DONE | Sanitize RequestLogger |
| S-006 | DONE | Add security headers |
| S-007 | DONE | Reduce token lifetime (365 -> 30 days) |
| R-001 | DONE | Add Task.Supervisor |
| R-002 | DONE | Fix fire-and-forget Tasks (11 instances) |
| R-003 | DONE | Replace IO.puts with Logger (CallChannel + 5 more files, Feb 15) |
| R-004 | DONE | Add GenServer timeouts (RoomStore, RoomPresenceServer, SimpleSensor, AttentionTracker) |
| R-005 | DONE | Centralize email sender config (Application.get_env + env var override) |
| R-006 | DONE | ETS write_concurrency on hot-path tables (Bio, PriorityLens, AttentionTracker) |
| R-007 | DONE | SafeKeys atom exhaustion fix (ConnectorServer, SensorServer) |
| R-008 | DONE | Dead code removal (duplicate watcher, legacy handlers) |
| R-009 | DONE | Bio.Supervisor explicit restart limits (max_restarts: 10, max_seconds: 60) |
| R-010 | DONE | Adaptive attention decay (load-correlated thresholds, two-tier cleanup) |
| R-011 | DONE | Honey badger AttentionTracker (crash-resilient restart, ETS preservation, re-register broadcast) |

---

## Files Modified

1. `config/dev.exs` - Move credentials, secrets
2. `config/prod.exs` - Enable check_origin
3. `config/config.exs` - Centralized mailer_from config
4. `config/runtime.exs` - Env-based mailer_from override
5. `lib/sensocto/application.ex` - Add Task.Supervisor
6. `lib/sensocto/otp/room_store.ex` - Use Task.Supervisor, GenServer timeouts
7. `lib/sensocto_web/plugs/request_logger.ex` - Sanitize logging
8. `lib/sensocto_web/endpoint.ex` - Add security headers
9. `lib/sensocto/accounts/user.ex` - Reduce token lifetime
10. `lib/sensocto_web/channels/call_channel.ex` - Replace IO.puts
11. `lib/sensocto/otp/room_presence_server.ex` - GenServer timeouts (8 client functions)
12. `lib/sensocto/registry_utils.ex` - IO.inspect/IO.puts -> Logger.debug
13. `lib/sensocto_web/live/lobby_live.ex` - IO.inspect -> Logger.debug
14. `lib/sensocto_web/live/index_live.ex` - IO.inspect -> Logger.debug
15. `lib/sensocto_web/live/sense_live.ex` - IO.puts/IO.inspect -> Logger.debug
16. `lib/sensocto/utils/otp_dsl_genserver.ex` - Removed compile-time IO.puts
17. `lib/sensocto/accounts/user/senders/*.ex` - Centralized mailer_from config
18. `lib/sensocto/bio/supervisor.ex` - Explicit restart limits
19. `lib/sensocto/otp/attention_tracker.ex` - Adaptive decay, honey badger crash resilience
20. `lib/sensocto_web/live/lobby_live.ex` - Re-register attention on tracker restart
21. `lib/sensocto_web/live/index_live.ex` - Re-register attention on tracker restart
22. `lib/sensocto_web/live/admin/system_status_live.ex` - Handle tracker restart message

---

## Post-Implementation Verification

After implementing all fixes:

1. Run test suite: `mix test`
2. Verify app starts: `mix phx.server`
3. Check credentials are read from env: `echo $DATABASE_URL`
4. Verify security headers in browser DevTools
5. Test WebSocket connections still work
