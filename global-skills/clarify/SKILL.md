shortDescription: Improve microcopy and interface text — every word must earn its place.
usedBy: [user]
version: 1.0.0
lastUpdated: 2026-03-20

## Purpose

Interface text is a design element. Weak microcopy undermines polished visuals — generic labels, vague error messages, and AI-generated filler copy signal the same lack of craft as vanilla shadcn/ui components. `/clarify` audits and improves all text in a UI: headings, labels, buttons, empty states, error messages, onboarding copy, and tooltips.

## When to Use

- After implementing any feature with significant user-facing copy
- When the UI text sounds like generic AI output ("Seamless", "Elevate", "Next-Gen")
- After `/polish` — text quality is part of the final quality pass
- When error messages are vague or unhelpful
- When empty states just show blank space or a generic message

## Microcopy Audit Checklist

### Headings & Labels

| Bad | Better | Why |
|-----|--------|-----|
| "Features" | "What you can build" | Concrete, user-oriented |
| "Pricing" | "Plans that scale with you" | Addresses the user's concern |
| "Dashboard" | "Your workspace" | Personalized |
| "Submit" | "Send message" / "Book call" / "Get started" | Specific action |
| "Click here" | "Download the report" | Descriptive of the outcome |
| "Learn more" | "See how it works" | Tells users what they'll find |

**Rule:** Every heading should tell the user what they get or what to do, not just label a section.

### Button Copy

- Buttons should state the outcome, not the action: "Save changes" not "Submit"
- Avoid generic: "OK", "Yes", "Click here" — use specific verbs matching the action
- Destructive actions must be unambiguous: "Delete account permanently" not "Confirm"
- Loading state copy: "Saving..." not just "Loading..."

### Error Messages

Every error message must answer:
1. **What happened?** (Specific, not "An error occurred")
2. **What should the user do?** (Actionable next step)

| Bad | Better |
|-----|--------|
| "Something went wrong" | "Couldn't save your changes — check your connection and try again" |
| "Error 404" | "This page doesn't exist — it may have moved or been deleted" |
| "Invalid input" | "Email address must include an @ symbol (e.g., name@example.com)" |
| "Operation failed" | "Upload failed — file must be under 10MB. Current file: 14MB" |
| "Please try again" | "Server error — we're on it. Try again in a minute, or contact support" |

### Empty States

An empty state is not a failure — it's an opportunity to guide. Every empty state must:
1. Explain what's empty and why
2. Tell the user how to populate it
3. Optionally, offer a shortcut to get started

```tsx
// Bad
<div>No items found.</div>

// Good
<div className="flex flex-col items-center gap-3 py-12 text-center">
  <InboxIcon className="h-10 w-10 text-muted-foreground" />
  <div>
    <h3 className="font-semibold">No projects yet</h3>
    <p className="text-sm text-muted-foreground mt-1">
      Create your first project to start tracking progress.
    </p>
  </div>
  <Button onClick={onCreate}>Create project</Button>
</div>
```

### Onboarding & First-Time Messages

- Explain what the user gains, not what the feature is: "Connect your calendar to see upcoming tasks" not "Calendar integration"
- Use "you" language: "Your workspace is ready" not "The workspace has been created"
- For confirmations: acknowledge completion + point to next step: "Password updated. You can now sign in with your new credentials."

### Tooltips

- Tooltips should add context, not repeat the label: `<Button title="Submit">Submit</Button>` — the tooltip adds nothing
- Good tooltip: hover over a disabled button → "You need editor permissions to publish"
- Good tooltip: hover over an icon button → "Mark as favorite (Shift+F)"

### AI Filler Words to Remove

These words signal that copy was AI-generated and not thought through:

```
Elevate | Seamless | Unleash | Next-Gen | Revolutionary
Empower | Transform | Leverage | Cutting-edge | Best-in-class
Game-changing | Unlock | Streamline | At your fingertips
```

Replace with concrete verbs and specific outcomes:
- "Elevate your workflow" → "Ship features 2× faster"
- "Seamless integration" → "Connects to Slack in 30 seconds"
- "Unleash your potential" → "Build and ship in one tool"

### Placeholder Text

- No "Lorem ipsum" in any production-facing component
- No generic names: "John Doe", "Jane Smith", "User 123" — use realistic, diverse names
- No predictable data: "99.99%", "1,234,567", "$100" — use organic-looking values

## Output Format

```
## Clarify Report

### Critical (confusing or misleading)
- [Location] "[current text]" → "[suggested text]" — Reason: [why it's confusing]

### High (generic or missed opportunity)
- [Location] "[current text]" → "[suggested text]"

### Low (minor polish)
- [Location] "[current text]" → "[suggested text]"

### AI filler detected
- [Location] "[phrase]" → remove or replace

### Missing states
- Empty state missing on: [component/page]
- Error state missing on: [component/page]
```

## Rules

- Microcopy is a design decision, not an afterthought. It belongs in the design pass, not a cleanup pass.
- Every error message must have an actionable next step.
- Every empty state must have a path forward.
- Audit copy against the brand personality adjectives in `design-profile.md` — tone must match.
- Never ship AI-generated filler phrases — they undermine credibility.
