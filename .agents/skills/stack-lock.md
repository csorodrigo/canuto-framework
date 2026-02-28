shortDescription: Prevents library drift by requiring personas to consult the approved stack before proposing dependencies.
version: 1.0.0
lastUpdated: 2026-02-28
copyright: Rodrigo Canuto © 2026.

## Purpose

Every project has a `.agents/stack.md` file that lists the approved library for each category. This skill defines the rules for using it.

---

## Rules

### For Architect

Before proposing any external dependency, you MUST:

1. Read `.agents/stack.md`.
2. Check if the category already has an approved library.
3. If yes: use it. Do not propose alternatives.
4. If the category is empty or `.agents/stack.md` does not exist: ask the user to choose, then record the decision in `.agents/stack.md`.

**Example:**
- Need state management? Check stack.md → "Zustand" → use Zustand. Done.
- Need a new category not listed? Ask the user, document the choice.

### For Coder

Before installing any package, check `.agents/stack.md`. If the package contradicts an approved library, escalate to Maestro before proceeding.

### For Reviewer

Flag as MUST FIX any new dependency that contradicts `.agents/stack.md`.

---

## Updating stack.md

Stack entries are changed only by explicit user decision. When a user approves a new library:

1. Record it in `.agents/stack.md` under the correct category.
2. Log the decision in `.agents/memory/decisions.md`.

Never change a stack entry based on personal preference or convenience.

---

## Categories

Standard categories (from `.agents/stack.md` template):

| Category | Examples |
|----------|---------|
| Auth | Clerk, Supabase Auth, NextAuth |
| UI | Tailwind + shadcn/ui, Chakra UI |
| State (client) | Zustand, Jotai |
| State (server) | React Query, SWR, Server Components |
| API | tRPC, Server Actions, REST |
| Database | Prisma + Neon, Prisma + Supabase |
| Payments | Stripe |
| Error tracking | Sentry, Highlight |
| Analytics | PostHog, Plausible |
| File uploads | UploadThing, Cloudinary |
| Search | Algolia, Typesense, Meilisearch |
| Realtime | Supabase Realtime, Pusher, Partykit |
