# GitHub Agent Automation

This project integrates Claude Code subagents with GitHub Issues and Projects for automated task management.

## Overview

The agent automation system allows you to:
- Dispatch specialized AI agents via GitHub Issues
- Track agent tasks in GitHub Projects
- Use issue templates for structured agent requests
- Trigger agents with `/agent` commands in issue comments

## Available Agents

| Agent | Purpose | Label |
|-------|---------|-------|
| security-advisor | Security analysis, auth hardening, OWASP checks | `agent:security-advisor` |
| api-client-developer | SDK development for Unity, Rust, Python, etc. | `agent:api-client-developer` |
| resilient-systems-architect | OTP patterns, supervision, fault tolerance | `agent:resilient-systems-architect` |
| livebook-tester | Interactive testing, Livebook documentation | `agent:livebook-tester` |
| elixir-test-accessibility | Accessibility compliance, test coverage | `agent:elixir-test-accessibility` |
| interdisciplinary-innovator | Cross-domain problem solving, biomimicry | `agent:interdisciplinary-innovator` |

## Usage

### Method 1: Issue Templates

1. Go to **Issues** → **New Issue**
2. Select the appropriate template:
   - Security Review Request
   - API Client Development
   - Architecture Review
   - Testing & Livebook Request
   - Accessibility & Test Review
   - Innovation & Brainstorm
3. Fill out the form and submit
4. The agent will be automatically assigned

### Method 2: Quick Command

In any issue comment, use:

```
/agent <agent-name> [action]
```

Examples:
```
/agent security-advisor analyze
/agent api-client-developer create Unity SDK
/agent resilient-systems-architect review supervision tree
```

### Method 3: Manual Labeling

Add the agent label directly to any issue:
1. Open the issue
2. Add label: `agent:security-advisor` (or any agent label)
3. The workflow will acknowledge and dispatch the agent

## Setup

### 1. Create Labels

Run the setup script:

```bash
gh auth login
./.github/scripts/setup-agent-labels.sh
```

### 2. Create GitHub Project

```bash
gh project create --owner adiibanez --title "Claude Agents" --body "Task tracking for Claude Code agents"
```

### 3. Configure Repository Variables

Set the project number for integration:

```bash
gh variable set AGENTS_PROJECT_NUMBER --body "<project-number>" --repo adiibanez/sensocto
```

Find your project number in the project URL: `github.com/users/adiibanez/projects/<number>`

## Workflow Details

The `.github/workflows/claude-agents.yml` workflow handles:

### Triggers

- **Issue opened with agent label**: Acknowledges assignment, adds to project
- **Issue labeled with agent label**: Same as above
- **Comment with `/agent` command**: Parses command and adds appropriate label

### Project Integration

When an agent is assigned:
1. Issue is added to the configured GitHub Project
2. Status can be tracked via project board columns
3. Agent reports are synced back as issue comments

### Status Labels

Track agent progress with status labels:

| Label | Meaning |
|-------|---------|
| `status:queued` | Task waiting for agent |
| `status:in-progress` | Agent actively working |
| `status:review` | Agent work complete, needs review |
| `status:blocked` | Needs human input |

## Agent Reports

Agent findings are stored in `.claude/agents/reports/`:

```
.claude/agents/reports/
├── security-advisor-report.md
├── api-client-developer-report.md
├── resilient-systems-architect-report.md
├── livebook-tester-report.md
├── elixir-test-accessibility-expert-report.md
└── interdisciplinary-innovator-report.md
```

When reports are updated (via push), the workflow comments on related open issues with a summary.

## Best Practices

1. **Be Specific**: Provide clear context in issue descriptions
2. **Include Files**: List relevant files/modules for the agent to review
3. **Set Priority**: Use priority fields in templates for urgent issues
4. **Follow Up**: Comment on issues to ask the agent follow-up questions
5. **Review Reports**: Check the agent reports in `.claude/agents/reports/` for detailed findings

## Troubleshooting

### Agent Not Responding

1. Check that the label was applied correctly
2. Verify the workflow ran (Actions tab)
3. Check workflow logs for errors

### Project Integration Not Working

1. Ensure `AGENTS_PROJECT_NUMBER` variable is set
2. Verify the project exists and is accessible
3. Check that the workflow has `issues: write` permission

### Labels Missing

Run the setup script again:
```bash
./.github/scripts/setup-agent-labels.sh
```
