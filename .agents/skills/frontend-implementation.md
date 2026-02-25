shortDescription: How to implement and evolve frontend features in this project.
usedBy: [coder, reviewer, architect]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## Purpose

Guide UI implementation (web/mobile) so that it:
- Follows the project's existing component, routing, and state patterns.
- Remains easy to understand and test.
- Stays aligned with the API and the Feature Map.

Works in both Canuto and foreign-schema projects.

---

## Procedure

### 1. Understand the UI Feature

1. Read the feature description (story, issue, Architect's plan).
2. Canuto project:
   - Review the corresponding flow in `docs/FEATURE-MAP.md`.
   - Read `.context.md` for UI directories (e.g., `apps/web`, `src/pages`, `src/components`).
3. Foreign-schema project:
   - Read design docs, storybook, frontend README, or equivalent.

### 2. Choose the Right Location for Code

1. Identify:
   - Where routes/pages live.
   - Where shared components live.
   - Where global state hooks/stores live.
2. Follow the existing structure:
   - Do not create new folders if an appropriate one already exists.
   - Use the project's file and component naming conventions.

### 3. Implement the UI

1. Create or update components:
   - Keep "presentational" components (layout/visual) separate from "container" components (data/state), if that pattern exists in the project.
   - Reuse existing components whenever possible instead of duplicating logic.
2. State and data:
   - Use the same state strategy already adopted (React state, context, Redux, Zustand, etc.).
   - For remote data, use the same client/fetcher and loading/error patterns used in other screens.
3. Accessibility and basic UX:
   - Use semantic elements (buttons, links, headings).
   - Keep loading/error feedback consistent with the rest of the app.

### 4. Connect with the API

1. Use `api-design` as reference:
   - Respect the API contract (fields, status codes, errors).
2. For each API call:
   - Handle states: idle, loading, success, error.
   - Do not swallow errors silently; show appropriate messages.

### 5. Update Context and Docs

1. Canuto project:
   - Update `.context.md` in the UI directory if:
     - You added screens, important components, or changed responsibilities.
   - If the feature is new or changed significantly:
     - Ensure `docs/FEATURE-MAP.md` has the complete updated flow (from UI entry point to backend).
2. Foreign-schema project:
   - Update whatever UI docs the project uses (README, storybook notes, etc.).

---

## Guardrails

- Do not introduce new UI/state libraries without approval; follow the existing stack.
- Do not put heavy business logic inside presentational components if the project avoids this.
- Do not change existing routing or navigation patterns without aligning with the Architect.
