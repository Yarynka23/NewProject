-include .env

COMPOSE := docker compose
DB_PORT ?= 5432
LOCAL_DATABASE_URL := $(subst @db:5432,@localhost:$(DB_PORT),$(DATABASE_URL))
s ?=

.DEFAULT_GOAL := help
.PHONY: help env build up down restart logs ps migrate migration seed psql test lint format \
	dev-backend dev-frontend install clean tf-init plan deploy cognito-env destroy infra-lint

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(firstword $(MAKEFILE_LIST)) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

env: ## Create .env from .env.example if missing
	@test -f .env || (cp .env.example .env && echo "Created .env")

build: env ## Build all images
	$(COMPOSE) build

up: env ## Build and start the whole stack
	$(COMPOSE) up -d --build
	@echo "App:      http://localhost:3000"
	@echo "API docs: http://localhost:8000/api/docs"

down: ## Stop the stack
	$(COMPOSE) down

restart: down up ## Restart the stack

logs: ## Follow logs (optionally: make logs s=backend)
	$(COMPOSE) logs -f $(s)

ps: ## Show running services
	$(COMPOSE) ps

migrate: ## Apply database migrations
	$(COMPOSE) exec backend alembic upgrade head

migration: ## Generate a migration: make migration m="add something" (db must be up)
	@test -n "$(m)" || (echo 'Usage: make migration m="message"' && exit 1)
	cd backend && DATABASE_URL=$(LOCAL_DATABASE_URL) uv run alembic revision --autogenerate -m "$(m)"

seed: ## Insert sample participants and meetings
	$(COMPOSE) exec backend python -m app.seed

psql: ## Open psql in the db container
	$(COMPOSE) exec db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

test: ## Run backend tests (against the <db>_test database)
	$(COMPOSE) exec backend pytest -v

lint: ## Lint backend and frontend
	cd backend && uv run ruff check . && uv run ruff format --check .
	cd frontend && npm run lint && npx prettier --check .

format: ## Format backend and frontend
	cd backend && uv run ruff check --fix . && uv run ruff format .
	cd frontend && npm run format

install: ## Install local dev dependencies (uv + npm)
	cd backend && uv sync
	cd frontend && npm install

dev-backend: env ## Run backend locally with reload (db runs in Docker)
	$(COMPOSE) up -d db
	cd backend && DATABASE_URL=$(LOCAL_DATABASE_URL) uv run alembic upgrade head
	cd backend && DATABASE_URL=$(LOCAL_DATABASE_URL) uv run uvicorn app.main:app --reload --port 8000

dev-frontend: ## Run Vite dev server on http://localhost:5173 (proxies /api to :8000)
	cd frontend && npm run dev

clean: ## Stop the stack and delete the database volume
	$(COMPOSE) down -v

# Terraform in infra/, with its state in HCP Terraform. Credentials and settings come from
# .env; export them only to the recipes below.
TF = $(TF_ENV) terraform -chdir=infra
TF_ENV := AWS_ACCESS_KEY_ID="$(AWS_ACCESS_KEY_ID)" AWS_SECRET_ACCESS_KEY="$(AWS_SECRET_ACCESS_KEY)" \
	$(if $(AWS_SESSION_TOKEN),AWS_SESSION_TOKEN="$(AWS_SESSION_TOKEN)") AWS_REGION="$(AWS_REGION)" \
	TF_TOKEN_app_terraform_io="$(TF_TOKEN_app_terraform_io)" \
	TF_CLOUD_ORGANIZATION="$(TF_CLOUD_ORGANIZATION)" TF_WORKSPACE="$(or $(TF_WORKSPACE),$(PROJECT_NAME),meetings)" \
	TF_VAR_project_name="$(or $(PROJECT_NAME),meetings)" TF_VAR_aws_region="$(AWS_REGION)" \
	TF_VAR_lambda_memory="$(or $(LAMBDA_MEMORY),512)" TF_VAR_extra_cors_origins="$(CORS_ORIGINS_AWS)" \
	TF_VAR_domain_name="$(DOMAIN_NAME)" TF_VAR_hosted_zone_id="$(HOSTED_ZONE_ID)" \
	TF_VAR_google_client_id="$(GOOGLE_CLIENT_ID)" TF_VAR_google_client_secret="$(GOOGLE_CLIENT_SECRET)"
COGNITO_KEYS := COGNITO_USER_POOL_ID COGNITO_CLIENT_ID COGNITO_DOMAIN COGNITO_GOOGLE_ENABLED

tf-init: env ## Connect infra/ to its HCP Terraform workspace and install the providers
	@$(TF) init

plan: env ## Show what make deploy would change on AWS
	@$(TF) plan

deploy: env ## Deploy the whole app to AWS (Terraform: infra, backend image, frontend upload)
ifneq ($(and $(DOMAIN_NAME),$(if $(HOSTED_ZONE_ID),,1)),)
	@# Without Route 53 the apply waits for a DNS record that is known only once the certificate exists.
	@$(TF) apply -auto-approve -target=module.frontend.aws_acm_certificate.this
	@echo "Add this DNS record at your DNS provider (if not done yet); the deploy waits for it:"
	@echo "  $$($(TF) output -raw certificate_validation_record)"
endif
	@$(TF) apply
	@$(MAKE) --no-print-directory cognito-env
	@echo "App:  $$($(TF) output -raw app_url) $$($(TF) output -raw custom_domain_url 2>/dev/null)"
	@echo "API:  $$($(TF) output -raw api_url)"
	@echo "Docs: $$($(TF) output -raw docs_url)"
ifneq ($(and $(DOMAIN_NAME),$(if $(HOSTED_ZONE_ID),,1)),)
	@echo "Point the domain at CloudFront: CNAME $(DOMAIN_NAME) -> $$($(TF) output -raw distribution_domain)"
endif

cognito-env: ## Write the Cognito settings (public ids) from the deployment to .env for local runs
	@for key in $(COGNITO_KEYS); do \
		value="$$($(TF) output -raw "$$(echo $$key | tr A-Z a-z)")" || exit 1; \
		grep -v "^$$key=" .env > .env.tmp; echo "$$key=$$value" >> .env.tmp; mv .env.tmp .env; \
	done
	@echo "Wrote $(COGNITO_KEYS) to .env"

destroy: env ## Delete the app from AWS (keeps the Cognito user pool and a final DB snapshot)
	@# The pool holds every account: dropping it from the state keeps it (and its prevent_destroy).
	@if $(TF) state list | grep -qx module.auth.aws_cognito_user_pool.this; then \
		echo "Keeping user pool $$($(TF) output -raw cognito_user_pool_id); delete it with aws cognito-idp delete-user-pool"; \
		$(TF) state rm module.auth.aws_cognito_user_pool.this; \
	fi
	@$(TF) destroy

infra-lint: ## Check formatting and validate the Terraform configuration
	terraform -chdir=infra fmt -check -recursive
	terraform -chdir=infra init -backend=false -input=false >/dev/null
	terraform -chdir=infra validate
