# Tidewave in Production

Tidewave is an AI debugging tool that connects Claude Code, Cursor, and other AI assistants to your running Phoenix application. While Tidewave is designed as a development tool, this guide explains how to safely enable it in production for trusted administrators.

## Overview

When enabled in production, Tidewave provides:
- **Code evaluation** - Execute Elixir code in the running application
- **SQL queries** - Direct database access via Ecto
- **Shell commands** - Execute bash commands on the server
- **Log access** - View application logs in real-time
- **Browser automation** - Interact with the web UI

## Security Model

Production Tidewave is protected by:

1. **HTTP Basic Authentication** - Credentials required for all `/tidewave/*` requests
2. **Runtime feature flag** - Disabled by default, must be explicitly enabled
3. **Origin checking** - Only allowed origins can make browser-based requests
4. **Audit logging** - All access attempts are logged

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ENABLE_TIDEWAVE` | Yes | Set to `true` to enable Tidewave |
| `TIDEWAVE_USER` | Yes | Username for Basic Auth |
| `TIDEWAVE_PASS` | Yes | Password for Basic Auth (use a strong, unique password) |

### Setting Up on Fly.io

```bash
# Generate a strong password
openssl rand -base64 32

# Set the secrets
fly secrets set ENABLE_TIDEWAVE=true
fly secrets set TIDEWAVE_USER=admin
fly secrets set TIDEWAVE_PASS=your-strong-password-here

# Deploy
fly deploy
```

### Accessing Tidewave

Once deployed, access Tidewave at:
```
https://sensocto.fly.dev/tidewave
```

You'll be prompted for Basic Auth credentials.

## Integration with AI Assistants

### Claude Code

Configure the MCP server in your Claude Code settings:

```json
{
  "mcpServers": {
    "sensocto-prod": {
      "command": "curl",
      "args": [
        "-u", "admin:your-password",
        "-X", "POST",
        "-H", "Content-Type: application/json",
        "https://sensocto.fly.dev/tidewave/mcp"
      ]
    }
  }
}
```

### Tidewave Desktop App

1. Open Tidewave Desktop App settings
2. Add a new connection:
   - URL: `https://sensocto.fly.dev/tidewave`
   - Enable "Remote Access"
   - Add credentials when prompted

## Risk Assessment

### Capabilities Exposed

| Capability | Risk Level | Mitigation |
|------------|------------|------------|
| Code evaluation | High | Strong credentials, audit logging |
| SQL queries | High | Read-only user option, query logging |
| Shell commands | Critical | Sandboxed container, limited tools |
| Log access | Medium | No sensitive data in logs |
| Browser control | Medium | Session isolation |

### Recommended Mitigations

1. **Rotate credentials regularly** - Change `TIDEWAVE_PASS` monthly
2. **Use IP allowlisting** - Configure Fly.io firewall if possible
3. **Monitor access logs** - Set up alerts for Tidewave access
4. **Limit to staging first** - Test in staging before enabling in production
5. **Time-limited access** - Disable when not actively debugging

## Disabling Tidewave

To disable Tidewave without redeploying:

```bash
fly secrets unset ENABLE_TIDEWAVE
# or
fly secrets set ENABLE_TIDEWAVE=false
```

The application will start returning 404 for all `/tidewave/*` requests immediately.

## Architecture

```
                                    ┌─────────────────────────┐
                                    │   Claude Code / Cursor  │
                                    │   (AI Assistant)        │
                                    └───────────┬─────────────┘
                                                │
                                                │ MCP Protocol
                                                │ + Basic Auth
                                                ▼
┌───────────────────────────────────────────────────────────────────┐
│                        Fly.io Edge                                │
│                    (TLS termination)                              │
└───────────────────────────────────────────────────────────────────┘
                                                │
                                                ▼
┌───────────────────────────────────────────────────────────────────┐
│                     Phoenix Endpoint                               │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │              AuthenticatedTidewave Plug                      │  │
│  │  1. Check ENABLE_TIDEWAVE flag                              │  │
│  │  2. Validate Basic Auth credentials                          │  │
│  │  3. Log access attempt                                       │  │
│  │  4. Delegate to Tidewave                                     │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                │                                   │
│                                ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                    Tidewave Router                           │  │
│  │  /tidewave/mcp    → MCP Server (code eval, SQL, logs)       │  │
│  │  /tidewave/shell  → Shell command execution                  │  │
│  │  /tidewave/       → Web UI                                   │  │
│  └─────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### "Not Found" when accessing /tidewave

Check that `ENABLE_TIDEWAVE` is set:
```bash
fly secrets list | grep TIDEWAVE
```

### "401 Unauthorized" errors

Verify credentials:
```bash
curl -u admin:password https://sensocto.fly.dev/tidewave/config
```

### Connection refused from AI assistant

Ensure `allow_remote_access: true` is set in the plug configuration and the origin is allowed.

## Files Modified

- `mix.exs` - Removed `only: :dev` from tidewave dependency
- `config/runtime.exs` - Added `enable_tidewave` config and Tidewave's required `project_name`/`root` config
- `lib/sensocto_web/endpoint.ex` - Added AuthenticatedTidewave plug for prod
- `lib/sensocto_web/plugs/authenticated_tidewave.ex` - Authentication wrapper

## Notes

Tidewave requires `project_name` and `root` configuration. In development, it auto-detects these via `Mix.Project`, but in production releases Mix isn't available. The runtime.exs now configures these explicitly when `ENABLE_TIDEWAVE=true`.

## See Also

- [Tidewave Documentation](https://hexdocs.pm/tidewave/)
- [Tidewave Security Guide](https://hexdocs.pm/tidewave/security.html)
- [Fly.io Secrets](https://fly.io/docs/reference/secrets/)
