# Deployment Guide: Standard vs Hot Code Upgrades

This guide covers two deployment strategies for Sensocto on Fly.io.

## Standard Deployment (Current)

Standard rolling deployments replace containers one at a time. This is the default and works for all changes.

### When to Use
- Dependency updates (`mix.exs` changes)
- Elixir/OTP version upgrades
- Supervision tree changes
- Major releases
- Any change that requires a full restart

### Deploy Command
```bash
fly deploy
```

### Behavior
- Machines restart one at a time
- WebSocket connections are dropped and reconnect
- LiveView sessions reset
- Process state is lost
- Health checks ensure traffic only goes to healthy machines

---

## Hot Code Upgrade Deployment (Optional)

Hot code upgrades update running code without restarting the BEAM VM, preserving WebSocket connections and process state.

### When to Use
- Bug fixes in module code
- UI/template changes
- Minor feature additions
- Changes that don't affect supervision tree or dependencies

### Prerequisites

1. **Install FlyDeploy package**

   Add to `mix.exs`:
   ```elixir
   {:fly_deploy, "~> 0.1"}
   ```

2. **Configure S3/Tigris storage**

   Using Fly Tigris:
   ```bash
   fly storage create
   fly secrets set AWS_ACCESS_KEY_ID=<key> AWS_SECRET_ACCESS_KEY=<secret>
   ```

3. **Add startup integration**

   In `lib/sensocto/application.ex`:
   ```elixir
   def start(_type, _args) do
     # Reapply hot code changes after container restart
     FlyDeploy.startup_reapply_current(Application.app_dir(:sensocto))

     children = [
       # ... existing children
     ]
     # ...
   end
   ```

4. **Add code_change callbacks** (for stateful GenServers)
   ```elixir
   @impl true
   def code_change(_old_vsn, state, _extra) do
     # Handle state migration if needed
     {:ok, state}
   end
   ```

### Deploy Command
```bash
mix fly_deploy.hot
```

### Behavior
- Code updates without VM restart
- WebSocket connections preserved
- LiveView sessions continue
- Process state maintained
- Automatic LiveView re-render

---

## Comparison

| Aspect | Standard Deploy | Hot Code Upgrade |
|--------|-----------------|------------------|
| WebSocket continuity | Lost | Preserved |
| Process state | Lost | Preserved |
| Setup complexity | None | Medium |
| Dependency updates | Supported | Not supported |
| Supervision changes | Supported | Not supported |
| OTP/Elixir upgrades | Supported | Not supported |
| Rollback | Deploy previous version | Deploy previous version |

---

## Limitations of Hot Code Upgrades

**Cannot use hot upgrades for:**
- Changes to supervision tree structure
- Adding/removing dependencies
- Updating Elixir or OTP versions
- Changes to application startup logic
- Database schema changes (migrations still run separately)

**Must use standard deploy for these changes.**

---

## Environment Variables

### Simulator Configuration
```bash
# Enable simulator in production
fly secrets set SIMULATOR_ENABLED=true

# Auto-start simulator connectors on boot
fly secrets set SIMULATOR_AUTOSTART=true

# Custom config path (optional)
fly secrets set SIMULATOR_CONFIG_PATH=config/simulators.yaml
```

---

## Recommended Workflow

1. **Development**: Use standard `fly deploy` for all changes
2. **Production hotfixes**: Consider `fly_deploy.hot` for urgent code-only fixes
3. **Major releases**: Always use standard `fly deploy`

When in doubt, use `fly deploy` - it's simpler and always works.
