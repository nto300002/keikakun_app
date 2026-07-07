.PHONY: backend-pytest backend-shell backend-alembic-current

ARGS ?=

backend-pytest:
	docker compose exec backend pytest $(ARGS)

backend-shell:
	docker compose exec backend bash

backend-alembic-current:
	docker compose exec backend sh -lc 'alembic heads && alembic current'

