# Mistral Copilot

Sovereign AI coding assistant. Runs [Mistral 7B Instruct](https://mistral.ai/news/announcing-mistral-7b) on CPU via [llama.cpp](https://github.com/ggerganov/llama.cpp). No GPU required.

Larger Mistral-family models — [Devstral Small 2](https://mistral.ai/news/devstral-2-vibe-cli) (24B), [Mistral Small Instruct](https://mistral.ai/news/mistral-small-3) (24B), and [Mistral Nemo Instruct](https://mistral.ai/news/mistral-nemo) (12B) — are available as opt-in models that download on first boot when selected.

## Quick Start

1. Import the appliance from the OpenNebula marketplace
2. Create a VM (4+ vCPU, 8 GB RAM is enough for the built-in Mistral 7B; bump to 16+ vCPU / 32 GB RAM if you select a 12B / 24B model)
3. Wait ~1 min for the built-in model to load (or ~5-10 min on first boot if you selected an opt-in model — it has to download from Hugging Face)
4. Get your API key: `ssh root@<vm-ip>` then `cat /etc/one-appliance/config`
5. Connect from VS Code with [Continue](https://continue.dev) or [Cline](https://cline.bot) pointing at `https://<vm-ip>:8443`

## Modes

**Standalone** (default): Single VM serving inference on port 8443 with TLS and API key auth.

**Load Balancer**: Enable `ONEAPP_COPILOT_LB_ENABLED=YES` to run a [LiteLLM](https://litellm.ai) proxy that distributes requests across multiple Mistral Copilot VMs with least-busy routing.

**Auto-registration**: Standalone VMs can register themselves with a remote LB on boot via `ONEAPP_COPILOT_REGISTER_URL`.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ONEAPP_COPILOT_AI_MODEL` | Mistral 7B Instruct (built-in) | Model selection from catalog (Mistral 7B built-in; Devstral 24B / Mistral Small 24B / Mistral Nemo 12B download on first boot when selected) |
| `ONEAPP_COPILOT_CONTEXT_SIZE` | 8192 | Context window (tokens). Larger values use more KV-cache RAM; raise only on VMs with memory to spare. |
| `ONEAPP_COPILOT_CPU_THREADS` | 0 (auto) | CPU threads for inference |
| `ONEAPP_COPILOT_API_PASSWORD` | (auto-generated) | API key / Bearer token |
| `ONEAPP_COPILOT_TLS_DOMAIN` | (self-signed) | FQDN for Let's Encrypt |
| `ONEAPP_COPILOT_TLS_EMAIL` | (empty) | Email for Let's Encrypt registration (recommended) |
| `ONEAPP_COPILOT_TLS_CA` | (empty) | Internal CA PEM (path or inline) to verify LB/backends |
| `ONEAPP_COPILOT_LB_ENABLED` | NO | Enable LiteLLM load balancer |
| `ONEAPP_COPILOT_LB_BACKENDS` | (empty) | Static backends (key@host:port) |
| `ONEAPP_COPILOT_REGISTER_URL` | (empty) | Remote LB URL for auto-registration (https only) |
| `ONEAPP_COPILOT_REGISTER_KEY` | (empty) | Remote LB master key |
| `ONEAPP_COPILOT_REGISTER_INSECURE` | NO | Allow registering to an unverified self-signed LB |
| `ONEAPP_COPILOT_REGISTER_MODEL_NAME` | (auto) | Model name for LB registration |
| `ONEAPP_COPILOT_REGISTER_SITE_NAME` | (empty) | Site name for backend ID |

## Access

| Endpoint | URL | Auth |
|----------|-----|------|
| API | `https://<vm-ip>:8443/v1` | Bearer token |
| Health | `https://<vm-ip>:8443/health` | None |
| Metrics | `https://<vm-ip>:8443/metrics` | None |
| LB Web UI | `https://<vm-ip>:8443/ui` | admin / UI password (in report) |

## License

Apache 2.0. Built-in model: Mistral 7B Instruct v0.3 (Apache 2.0, Mistral AI). Opt-in models — Devstral Small 2 24B, Mistral Small Instruct 24B, Mistral Nemo Instruct 12B — all Apache 2.0 from Mistral AI.

## Author

Pablo del Arco, [OpenNebula Systems](https://opennebula.io).
