# Meetings App

List, create, and delete meetings with participants. FastAPI + PostgreSQL backend, React + shadcn/ui frontend, all run with Docker Compose. See [SPEC.md](SPEC.md) for the full specification.

## Quick start

Requires Docker.

```sh
make up      # creates .env from .env.example, builds and starts everything
make seed    # optional: sample participants and meetings
```

- App: http://localhost:3000
- API docs: http://localhost:8000/api/docs

If port 5432 is already in use on your machine, set `DB_PORT` in `.env` (e.g. `DB_PORT=5433`).

## Create a meeting with AI

**Create with AI** opens a dialog where you describe the meeting by typing or by voice, e.g. *"Sprint planning tomorrow 3–4pm in room 204 with Olena and Taras"*. The backend transcribes speech with OpenAI (`OPENAI_TRANSCRIPTION_MODEL`) and turns the text into form values with OpenAI structured outputs (`OPENAI_MODEL`). It resolves relative dates against your local time and matches people to existing participants. The result opens in the regular meeting form, and nothing is saved until you check it and click **Create meeting**.

Set `OPENAI_API_KEY` in `.env` and restart (`make restart`). Without a key the rest of the app works as usual and the assistant reports that it is not configured. Recordings are limited to 2 minutes.

## Common commands

Run `make` to list all targets. The most used:

| Command | What it does |
|---|---|
| `make up` / `make down` | Start / stop the stack |
| `make logs s=backend` | Follow logs of one service |
| `make test` | Backend tests (in the backend container, against `<db>_test`) |
| `make lint` / `make format` | Ruff + oxlint/Prettier |
| `make migration m="..."` | Autogenerate an Alembic migration |
| `make psql` | Open a psql shell |
| `make clean` | Stop and delete the database volume |

## Local development without rebuilding images

Requires [uv](https://docs.astral.sh/uv/) and Node.js.

```sh
make install        # uv sync + npm install
make dev-backend    # Postgres in Docker, API on :8000 with reload
make dev-frontend   # Vite on :5173, proxies /api to :8000
```

## Deploy to AWS

<<<<<<< HEAD
Auth, the weekly report and the agenda parser are Terraform (run by HCP Terraform); the rest is CloudFormation. Everything lives in [`infra/`](infra/) and deployed to `us-east-1` by default (`AWS_REGION` in `.env`):
=======
Everything is described with Terraform in [`infra/`](infra/) and deployed to `us-east-1` by default (`AWS_REGION` in `.env`). The state is stored in [HCP Terraform](https://app.terraform.io):
>>>>>>> upstream/main

- **Backend** (`infra/modules/backend`): the backend container on AWS Lambda (via [Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter), so the FastAPI app runs unchanged), exposed through a public **Lambda function URL**, and its PostgreSQL 17 database on **Aurora Serverless v2 scaling between 0 and 1 ACU**. After 5 idle minutes the database pauses and costs only storage; the first request after that waits about 15 seconds while it resumes. The function runs in the database's private subnets; there is no NAT gateway, load balancer or public IP. The image is tagged with a hash of the backend sources and rebuilt only when they change.
- **Frontend** (`infra/modules/frontend`): the app, built with `VITE_API_URL` set to the function URL, in a private S3 bucket behind CloudFront on **pay-as-you-go** pricing (`PriceClass_100`). The browser calls the function URL directly; the CloudFront address (and custom domain) are the backend's CORS origins. It is rebuilt and uploaded only when its sources or settings change.
- **Auth** (`infra/modules/auth`): the Cognito user pool and app client.

1. In HCP Terraform, create an organization and a workspace named like `PROJECT_NAME` (CLI-driven workflow), and set the workspace's **Settings → General → Execution Mode** to **Local**: plans and applies run on your machine (they build the Docker image and the frontend), only the state is stored in HCP Terraform.
2. Put into `.env` the AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`) and the HCP Terraform settings (`TF_TOKEN_app_terraform_io`, `TF_CLOUD_ORGANIZATION`, optionally `TF_WORKSPACE`); see `.env.example`. `.env` is gitignored.
3. `make tf-init` once, then `make deploy`. It shows the plan, applies it after you confirm, writes the Cognito ids to `.env` (for local runs) and prints the app and API URLs. The first run takes about 20 minutes (database and CloudFront distribution). `make plan` only shows the changes.
4. `make destroy` deletes everything except the Cognito user pool (with its accounts) and a final database snapshot.

Requires Terraform, Docker, Node.js and the AWS CLI. `make infra-lint` checks the configuration.

### Infrastructure as code (Terraform)

Cognito (`auth.tf`), the weekly report (`reports.tf`) and the agenda parser (`ai.tf`) are described in Terraform in [`infra/`](infra/). State lives in the HCP Terraform workspace `meetings-dev`; nobody applies from a laptop.

- Change infrastructure: edit the `.tf` files, open a pull request, read the plan in the HCP Terraform check, merge. HCP Terraform applies the merge to `main`.
- Preview locally: `make infra-plan` (needs `terraform login`). Format: `make infra-fmt`.
- After a change to Cognito, run `make auth-env` to refresh the settings in `.env` from the Terraform outputs.
- Secrets (`google_client_secret`, `db_password`) are sensitive variables in the workspace, never in Git.

### Custom domain

Set the domain in `.env` and run `make deploy`:

```sh
DOMAIN_NAME=app.example.com
HOSTED_ZONE_ID=Z0123456789ABC   # optional: only if the domain's DNS is in Route 53
```

This requests an ACM certificate in `us-east-1` (the only region CloudFront accepts) and adds the domain to the CloudFront distribution, the backend's CORS origins and Cognito's redirect URLs. With `HOSTED_ZONE_ID`, the validation and alias records are created in Route 53. Without it, `make deploy` first prints the validation CNAME to add at your DNS provider, waits for the certificate, and at the end prints the CNAME that points the domain at CloudFront. To remove or switch the domain, change `DOMAIN_NAME` and run `make deploy` again.

### Tags

Every AWS resource that supports tags is tagged `PROJECT_NAME=<PROJECT_NAME>` (the AWS provider's `default_tags`). Find the whole app with Resource Groups & Tag Editor, and split out its costs in Billing once `PROJECT_NAME` is activated as a cost allocation tag.

## Layout

```
backend/    FastAPI app (app/), Alembic migrations (alembic/), tests (tests/)
frontend/   Vite + React + shadcn/ui (src/components/ui is generated by shadcn)
<<<<<<< HEAD
infra/      Terraform (auth, reports, ai) and CloudFormation templates with deploy scripts for the rest
=======
infra/      Terraform configuration for AWS (modules/: auth, backend, frontend)
>>>>>>> upstream/main
```
