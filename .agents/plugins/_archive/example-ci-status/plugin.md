---
name: ci-status
version: 1.0.0
description: Check CI/CD pipeline status and suggest fixes for failed builds
author: canuto-framework
requires:
  - audit-trail
compatible: ">=1.6.0"
---

# CI Status Plugin

Integrates CI/CD pipeline status into Canuto sessions. Allows Maestro to check build status, report failures, and suggest fixes based on error logs.

## Skills Provided

| Skill | Trigger | Description |
|-------|---------|-------------|
| `ci-status` | `/ci-status` | Check current CI pipeline status |

## Setup

1. Copy this plugin to `.agents/plugins/example-ci-status/` in your project
2. Set the CI provider in your CLAUDE.md:
   ```markdown
   ## Plugins
   - ci-status:
     provider: github-actions  # or: gitlab-ci, circleci
   ```

## How It Works

- On `/ci-status`, reads the latest CI run via `gh run list` (GitHub Actions)
- Reports: status, failed jobs, error logs
- Suggests fixes based on common failure patterns
- Logs check as audit event (`CI_CHECK`)

## Notes

This is an **example plugin** to demonstrate the Canuto plugin structure. Use it as a template for creating your own plugins.
