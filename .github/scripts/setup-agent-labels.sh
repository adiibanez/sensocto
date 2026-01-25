#!/bin/bash
# Setup GitHub labels for Claude Agent automation
# Run with: gh auth login && ./.github/scripts/setup-agent-labels.sh

set -e

REPO="adiibanez/sensocto"

echo "Setting up agent labels for $REPO..."

# Agent labels (purple theme)
gh label create "agent:security-advisor" --description "Security analysis by security-advisor agent" --color "7B1FA2" --repo "$REPO" --force
gh label create "agent:api-client-developer" --description "API client development agent" --color "512DA8" --repo "$REPO" --force
gh label create "agent:resilient-systems-architect" --description "Architecture review by resilient-systems-architect" --color "4527A0" --repo "$REPO" --force
gh label create "agent:livebook-tester" --description "Testing and Livebook creation agent" --color "6A1B9A" --repo "$REPO" --force
gh label create "agent:elixir-test-accessibility" --description "Accessibility and test coverage agent" --color "8E24AA" --repo "$REPO" --force
gh label create "agent:interdisciplinary-innovator" --description "Cross-domain innovation agent" --color "9C27B0" --repo "$REPO" --force

# Status labels (for project tracking)
gh label create "status:queued" --description "Task queued for agent" --color "FFA726" --repo "$REPO" --force
gh label create "status:in-progress" --description "Agent is working on this" --color "29B6F6" --repo "$REPO" --force
gh label create "status:review" --description "Agent work complete, needs review" --color "66BB6A" --repo "$REPO" --force
gh label create "status:blocked" --description "Agent blocked, needs human input" --color "EF5350" --repo "$REPO" --force

# Category labels
gh label create "security" --description "Security related" --color "D32F2F" --repo "$REPO" --force
gh label create "sdk" --description "SDK/Client library related" --color "1976D2" --repo "$REPO" --force
gh label create "architecture" --description "Architecture and design" --color "388E3C" --repo "$REPO" --force
gh label create "testing" --description "Testing related" --color "F57C00" --repo "$REPO" --force
gh label create "accessibility" --description "Accessibility related" --color "00897B" --repo "$REPO" --force
gh label create "innovation" --description "Research and innovation" --color "5E35B1" --repo "$REPO" --force

echo "Labels created successfully!"
echo ""
echo "Next steps:"
echo "1. Create a GitHub Project for agent tasks:"
echo "   gh project create --owner adiibanez --title 'Claude Agents' --body 'Task tracking for Claude Code agents'"
echo ""
echo "2. Set the project number in repository variables:"
echo "   gh variable set AGENTS_PROJECT_NUMBER --body '<project-number>' --repo $REPO"
