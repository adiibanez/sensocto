# Deployment Guide: Standard vs Hot Code Upgrades

This guide covers two deployment strategies for Sensocto on Fly.io.

## Standard Deployment

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

## Hot Code Upgrade Deployment

Hot code upgrades update running code without restarting the BEAM VM, preserving WebSocket connections and process state.

### When to Use
- Bug fixes in module code
- UI/template changes
- Minor feature additions
- Changes that don't affect supervision tree or dependencies

---

## One-Time Setup (Already Done)

The following has already been configured in this project:

1. **FlyDeploy package** added to `mix.exs`:
   ```elixir
   {:fly_deploy, "~> 0.1.15"}
   ```

2. **Startup integration** in `lib/sensocto/application.ex`:
   ```elixir
   if Code.ensure_loaded?(FlyDeploy) do
     FlyDeploy.startup_reapply_current(Application.app_dir(:sensocto))
   end
   ```

3. **Runtime config** in `config/runtime.exs`:
   ```elixir
   if bucket = System.get_env("FLY_DEPLOY_BUCKET") do
     config :fly_deploy, bucket: bucket
   end
   ```

---

## Fly.io Setup (Run Once)

### Step 1: Create Tigris Storage Bucket
```bash
fly storage create
```
When prompted:
- Choose a name (e.g., `sensocto-deploy`)
- This automatically sets `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` secrets

### Step 2: Set the Bucket Name
```bash
fly secrets set FLY_DEPLOY_BUCKET=<bucket-name-from-step-1>
```

### Step 3: Create Machine Exec Token
```bash
fly secrets set FLY_API_TOKEN=$(fly tokens create machine-exec)
```

### Step 4: Initial Standard Deploy
Deploy with the new fly_deploy package:
```bash
fly deploy
```

---

## Using Hot Deploy

After setup is complete:

### Make a Code Change
For example, edit `lib/sensocto_web/components/layouts/root.html.heex`:
```html
<!-- Change navbar text -->
<a href="/simulator">Simulator</a>
<!-- to -->
<a href="/simulator">Sim</a>
```

### Deploy with Hot Upgrade
```bash
mix fly_deploy.hot
```

### What Happens
1. Mix task builds a tarball of changed `.beam` files
2. Uploads tarball to Tigris storage
3. Triggers RPC to each running machine
4. Each machine downloads and loads new code
5. LiveView processes automatically re-render
6. WebSocket connections stay connected

---

## Comparison

| Aspect | Standard Deploy | Hot Code Upgrade |
|--------|-----------------|------------------|
| WebSocket continuity | Lost | Preserved |
| Process state | Lost | Preserved |
| Setup complexity | None | Medium (one-time) |
| Dependency updates | Supported | Not supported |
| Supervision changes | Supported | Not supported |
| OTP/Elixir upgrades | Supported | Not supported |
| Rollback | `fly deploy` previous | `fly deploy` previous |

---

## Limitations of Hot Code Upgrades

**Cannot use hot upgrades for:**
- Changes to supervision tree structure
- Adding/removing dependencies
- Updating Elixir or OTP versions
- Changes to application startup logic
- Database schema changes (migrations still run separately)
- NIFs or native code changes

**Must use standard `fly deploy` for these changes.**

---

## Environment Variables Reference

### Hot Deploy
```bash
FLY_DEPLOY_BUCKET      # Tigris bucket name for beam artifacts
AWS_ACCESS_KEY_ID      # Tigris access key (auto-set by fly storage create)
AWS_SECRET_ACCESS_KEY  # Tigris secret key (auto-set by fly storage create)
FLY_API_TOKEN          # Machine exec token for orchestration
```

### Simulator Configuration
```bash
SIMULATOR_ENABLED=true       # Enable simulator in production
SIMULATOR_AUTOSTART=true     # Auto-start connectors on boot
SIMULATOR_CONFIG_PATH=...    # Custom config path (optional)
```

---

## Troubleshooting

### "No bucket configured"
```bash
fly secrets set FLY_DEPLOY_BUCKET=your-bucket-name
```

### "AWS credentials not found"
```bash
fly storage create  # Creates bucket and sets credentials
```

### "FLY_API_TOKEN not set"
```bash
fly secrets set FLY_API_TOKEN=$(fly tokens create machine-exec)
```

### Hot deploy fails silently
Check logs:
```bash
fly logs
```

### Need to rollback
Use standard deploy with previous version:
```bash
fly deploy
```

---

## Recommended Workflow

1. **Standard deploy first** - Always do initial deploy with `fly deploy`
2. **Hot deploy for fixes** - Use `mix fly_deploy.hot` for code-only changes
3. **Standard deploy for major changes** - Dependencies, config, supervision tree

When in doubt, use `fly deploy` - it's simpler and always works.
