# Testing & lint conventions (loan-webapp, lending-webapp)

Both units use the same setup, established 2026-07-20:

- **Unit tests:** Vitest + Supertest. Config: `vitest.config.ts` (`include: ["test/**/*.test.ts"]`).
  Tests live in `test/`, not `src/` — `tsconfig.json` scopes `include` to `src/**/*` so `tsc`
  (the production build) never touches test files.
- **Mocking:** `vi.mock("fs")` for data-store tests, `vi.mock("https")` for `events.ts`'s
  `notifyApp`, and `vi.mock("../src/data/<store>")` + `vi.mock("../src/events")` for route tests
  (supertest against the exported `app`). No real file or network I/O in tests.
- **Testable app split:** `src/app.ts` exports the configured Express `app` (routes, middleware,
  no `listen`, no cert reads). `src/server.ts` is the thin bootstrap — imports `app`, reads certs,
  calls `https.createServer(...).listen(...)`. Import `app.ts` in tests, never `server.ts`
  (importing `server.ts` starts a real HTTPS listener and reads cert files as a side effect).
- **Lint/format:** ESLint flat config (`eslint.config.js`, typescript-eslint recommended, scoped
  to `**/*.ts` vs `**/*.js` so `require()` is allowed in plain-JS config/scripts but not app code)
  + Prettier (`.prettierrc.json`: 4-space indent, double quotes, 100 print width).
- **Scripts:** `npm test` / `test:watch`, `npm run lint` / `lint:fix`, `npm run format` /
  `format:check`.
- **Node version:** both Dockerfiles pin `node:22-alpine` (bumped from `node:18-alpine` — Vitest 4
  and ESLint 10 require Node >=20).

New unit tests for these apps should follow this pattern rather than introducing a second test
framework or mocking strategy.
