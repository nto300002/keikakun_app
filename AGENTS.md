# Repository Instructions

## Backend Execution

- Backend commands must run in Docker by default.
- Do not run backend pytest with host `pytest`, `python -m pytest`, or a host `.venv` unless the user explicitly asks for host execution.
- Use the existing Compose service:

```bash
docker compose exec backend pytest
```

- For a specific backend test file or marker, pass arguments through Docker:

```bash
docker compose exec backend pytest tests/api/v1/test_csrf_protection.py
docker compose exec backend pytest tests/api/v1/test_csrf_protection.py -m "not performance"
```

- If Docker daemon access is denied by the sandbox, request approval and rerun the same Docker command with elevated permissions.
- Treat container results as the source of truth for backend dependencies, environment variables, and pytest behavior.
- If the backend container exits before Python starts with `Too many open files: '/app'`, treat it as a Docker Desktop bind-mount issue around `./k_back:/app`, not as a DB, Alembic, or pytest failure.
- In that failure mode, first inspect container state and logs with `docker compose ps` and `docker logs --tail=80 keikakun_app-backend-1`. For read-only diagnostics that do not need application imports, run Python from `/tmp` with `PYTHONPATH` unset inside the backend container:

```bash
docker compose run --rm --entrypoint sh backend -lc 'cd /tmp && unset PYTHONPATH && python - <<"..."
print("python_ok")
...
'
```

- Do not use the `/tmp`/`PYTHONPATH` workaround for backend tests or application behavior checks. It is only for environment diagnostics such as read-only DB metadata checks when `/app` cannot be opened.

## Frontend Execution

- Frontend commands run from `k_front`.
- Prefer existing npm scripts over ad hoc commands.

## Editing

- Prefer structured file edits through the normal patch/edit tool.
- Avoid `sed -i` for source edits unless the change is mechanical and clearly safer that way.

## DevGuard Before Commit and Push

- Before committing, run DevGuard against the staged diff:

```bash
npx --yes @nto300002/devguard check --staged-diff
```

- Before pushing, run DevGuard against the branch diff:

```bash
npx --yes @nto300002/devguard push-check --agent-block
```

- Read the DevGuard output before continuing. Treat high-risk findings as blockers unless the user explicitly approves proceeding.
- When DevGuard reports warnings, findings, or manual-check items, summarize the relevant output to the user and ask for confirmation before commit or push.
- Do not ignore DevGuard suppression comments unless they include a concrete reason.

## Backend Architecture

- Follow the existing layered architecture:
  - API layer: `k_back/app/api/v1/endpoints`
  - Service layer: `k_back/app/services`
  - CRUD layer: `k_back/app/crud`
  - Model/schema layer: `k_back/app/models`, `k_back/app/schemas`
- API endpoints should handle HTTP concerns, auth/authorization, request validation, and response shaping.
- Business logic and multi-model workflows should live in services.
- CRUD modules should stay focused on data access for a single model or narrow aggregate.

## Commit, Flush, and Transactions

- API layer must not introduce new `await db.commit()` or `await db.flush()` calls.
- Service layer owns transaction boundaries for multi-step business logic and multiple CRUD operations.
- CRUD may `flush()` when generated IDs are needed.
- CRUD may `commit()` only for simple single-model operations that are intentionally not coordinated by a service.
- Do not split one business operation across multiple commits unless there is a deliberate recovery/retry design.
- On exceptions around committed service workflows, rollback before re-raising.
- Avoid long-running transactions. Keep external API calls and large loops outside open DB transactions where practical.
- Do not nest transaction boundaries casually. Prefer one clear commit at the business use-case boundary.

## Database Changes

- Alembic migrations are the source of truth for DB definition/data migrations.
- Put migrations in `k_back/migrations/versions/`.
- Do not treat manual SQL files as the normal deployment path.
- Manual SQL is only for investigation, verification, emergency remediation, or rollback notes.
- For enum changes, constraints, columns, indexes, and data migrations, document verification steps or counts.
- `alembic stamp` is a managed operation, not a normal local or CI migration step.
- Before pushing CI/CD or migration-related changes, inspect the workflow and Cloud Build substitutions against the actual repository secret names. Confirm that DB connection variables are intentionally mapped, for example `PROD_DATABASE_URL` for production and the configured test DB secret such as `TEST_DATABASE_URL` for the production-test branch when no `PROD_TEST_DATABASE_URL` secret exists.
- Do not introduce references to non-existent DB secrets in GitHub Actions. If a workflow passes a DB URL into Cloud Build, verify both sides: the GitHub Actions `secrets.*` name and the Cloud Build `_SUBSTITUTION`/`DATABASE_URL` environment name.
- Current GitHub Actions secret names confirmed for this repository are:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_REGION`
  - `AWS_SECRET_ACCESS_KEY`
  - `CALENDAR_ENCRYPTION_KEY`
  - `COOKIE_DOMAIN`
  - `COOKIE_SAMESITE`
  - `COOKIE_SECURE`
  - `E2E_API_URL`
  - `E2E_DATABASE_URL`
  - `E2E_OWNER_EMAIL`
  - `E2E_OWNER_PASSWORD`
  - `E2E_SECRET_KEY`
  - `E2E_STAFF_PASSWORD`
  - `E2E_STRIPE_PUBLISHABLE_KEY`
  - `E2E_VAPID_PUBLIC_KEY`
  - `ENVIRONMENT`
  - `FRONTEND_URL`
  - `GCP_PROJECT_ID`
  - `GCP_SA_KEY`
  - `MAIL_PASSWORD`
  - `MAIL_PORT`
  - `MAIL_SERVER`
  - `MAIL_USERNAME`
  - `PASSWORD_RESET_TOKEN_EXPIRE_MINUTES`
  - `PLAYWRIGHT_BASE_URL`
  - `PROD_DATABASE_URL`
  - `PROD_SECRET_KEY`
  - `RATE_LIMIT_FORGOT_PASSWORD`
  - `RATE_LIMIT_RESEND_EMAIL`
  - `S3_ACCESS_KEY`
  - `S3_BUCKET_NAME`
  - `S3_REGION`
  - `S3_SECRET_KEY`
  - `SENDER_EMAIL`
  - `STRIPE_PRICE_ID`
  - `STRIPE_PUBLISHABLE_KEY`
  - `STRIPE_SECRET_KEY`
  - `STRIPE_WEBHOOK_SECRET`
  - `TEST_DATABASE_URL`
  - `VAPID_PRIVATE_KEY`
  - `VAPID_PUBLIC_KEY`
- `ENCRYPTION_KEY` is not currently configured as a GitHub Actions secret. Do not reference `secrets.ENCRYPTION_KEY` unless the secret is explicitly added. For current production MFA compatibility, Cloud Build `_ENCRYPTION_KEY` should be mapped from the existing `secrets.PROD_SECRET_KEY` unless a deliberate key-rotation plan is implemented.

## Maintainability

- Prefer small, responsibility-based refactors over broad rewrites.
- Fix behavior with tests first when changing existing auth, billing, notification, recipient, support-plan, or calendar flows.
- Avoid duplicating business rules. Move shared logic to services/helpers where the existing codebase pattern supports it.
- Keep functions and components single-purpose. Split by responsibility, not merely by line count.
- Use clear Python naming:
  - CRUD: `create_*`, `get_*`, `update_*`, `delete_*`
  - validation: `validate_*`
  - checks: `check_*`
  - booleans: `is_*`, `has_*`, `can_*`
- Replace magic numbers with named constants when the value encodes business policy.
- User-facing backend error messages should be Japanese and preferably centralized in `app/messages/ja.py`.
- Comments should explain why, not restate obvious code. Use docstrings for public service/helper behavior where useful.
- Prefer early returns to deeply nested conditional logic.

## Logging and Sensitive Data

- Do not use `print()` in backend production code.
- Avoid unconditional `console.log` in frontend production code.
- Do not log tokens, cookies, email addresses, personal names, internal IDs, support-plan text, filenames, Stripe secrets/IDs, Google credentials, MFA secrets, QR URIs, or recovery codes unless explicitly masked.
- Prefer fixed messages plus safe metadata such as error type, status code, counts, or boolean presence flags.
- Success-path detail logs should usually be `debug`; operational failures should use `warning` or `error` without sensitive payloads.

## Project-Specific Refactoring Priorities

- Keep auth cookie option generation centralized rather than duplicating `domain`, `path`, `secure`, `samesite`, and `max_age` logic in endpoints.
- Separate large backend services by responsibility: decision logic, DB updates, notification creation, external API calls, and audit logging.
- Separate large frontend components into container/state hooks, API adapters, permission helpers, and presentational components.
- Consolidate role-change and employee-action notification/audit flows where behavior is shared, while keeping business-specific differences explicit.
- Treat Google Calendar sync as an optional side effect. Support-plan creation/deletion should not depend on Google API success.
- Keep billing status transition rules centralized so webhook, batch, and API paths call the same transition logic.
- Split `get_current_user` dependencies by need: minimal auth, office-loaded auth, and role-specific requirements.
- Classify TODOs as specification-unknown, unimplemented, deletion candidate, or development-only. Do not leave user-facing fake data, fake waits, or disconnected UI without an issue/task.

## Useful Checks

Run these through Docker for backend where applicable:

```bash
docker compose exec backend sh -lc 'rg "await db.commit\\(|await db.flush\\(" app/api/v1/endpoints'
docker compose exec backend sh -lc 'rg "print\\(" app --type py'
docker compose exec backend sh -lc 'rg "HTTPException.*detail=\"[A-Za-z]" app/api --type py'
docker compose exec backend sh -lc 'alembic heads && alembic current'
```

Frontend checks:

```bash
rg 'console\.log' k_front/app k_front/components k_front/lib --glob '*.ts' --glob '*.tsx'
```
