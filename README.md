# Supply Chain Pipeline

[![CI](https://github.com/barthez-kenwou/supply-chain-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/barthez-kenwou/supply-chain-pipeline/actions/workflows/ci.yml)
[![Security](https://github.com/barthez-kenwou/supply-chain-pipeline/actions/workflows/security.yml/badge.svg)](https://github.com/barthez-kenwou/supply-chain-pipeline/actions/workflows/security.yml)
[![Release Image](https://github.com/barthez-kenwou/supply-chain-pipeline/actions/workflows/release.yml/badge.svg)](https://github.com/barthez-kenwou/supply-chain-pipeline/actions/workflows/release.yml)

**Live demo:** [supply-chain-demo.barthez-kenwou.dev](https://supply-chain-demo.barthez-kenwou.dev/)  
**Repo:** [barthez-kenwou/supply-chain-pipeline](https://github.com/barthez-kenwou/supply-chain-pipeline)

OCI **supply-chain kit** — reusable DevSecOps backbone for shipping a container to production without “push and pray”.

This is a **portfolio / template** project: a guided static site on nginx (tabs: résumé, pipeline détaillée, architectures animées, décisions, retours terrain, réutilisation), plus the full delivery chain I designed and ran in production on [zenora360.com](https://zenora360.com).

> Quality → Security → build → Trivy gate → Harbor → Cosign + SBOM + provenance → digest deploy over SSH → smoke on a reverse-proxy Docker network.

---

## Why this exists

Most “CI demos” stop at green unit tests. Here the point is the **path to prod**:

- nothing lands in the registry before an image scan gate
- deploy never uses `latest`
- Cosign verify happens **before** SSH
- runtime sits behind Nginx Proxy Manager on a shared Docker network — no hijacking host `:80`
- when Harbor Cosign policy returns HTTP 412 on pull, Deploy loads the signed release artifact after verify

The `app/` folder is the showcase UI (static HTML/CSS/JS). Swap it for your real service; keep `.github/` + `deploy/`.

---

## Showcase UI

The live page is a **guide**, not a deco landing:

| Onglet | Contenu |
| ------ | ------- |
| Résumé | pitch, principes fail-closed, preuve de vie |
| Pipeline | CI → SAST/SCA → DAST → Release → Sign/SBOM → Deploy, outils + pourquoi |
| Intégrer | guide pas à pas : greffer le kit sur un autre projet (Harbor, VPS, secrets, premier vert) |
| Architecture | workflows, séquence release, runtime proxy (animés) |
| Décisions | justifications (digest, keyless, Trivy-before-push, SSH mux…) |
| Retours terrain | Harbor 412, CodeQL `actions`, crane, UFW, Dependabot, CF 403 |

---

## Pipeline map

```mermaid
flowchart TB
  PR[PR / push] --> CI[CI]
  PR --> SEC[Security]
  MAIN[merge main] --> REL[Release Image]
  REL -->|workflow_run + metadata + release-image| DEP[Deploy]
  DEP --> HOST[VPS · Compose · reverse proxy]
```

| Workflow | Role |
| -------- | ---- |
| `ci.yml` | Hadolint, gitleaks, build + `/health`, SonarQube QG (si `SONAR_*`) |
| `security.yml` | Trivy fs/config, CodeQL (`actions`), ZAP (weekly / manual) |
| `release.yml` | build → Trivy image → push → Cosign → SBOM → provenance + `release-image` artifact |
| `deploy.yml` | verify digest → SSH mux → load/pull → health / rollback → smoke |

Technical deep-dive: [`.github/README.md`](.github/README.md).

---

## Quick local run

```bash
make compose-up
curl -fsS http://127.0.0.1:8080/health   # OK
# open http://127.0.0.1:8080/
```

---

## Reuse on another product

1. Copy `.github/` + `deploy/` (+ compose if the proxy model fits).
2. Change `IMAGE_NAME` (`supply-chain-web` → yours).
3. Wire Harbor + SSH secrets (see `.github/README.md`).
4. Point your reverse proxy at `container:8080` on `PROXY_NETWORK`.

---

## Production proof

The same discipline powers **ZENORA Web** ([zenora360.com](https://zenora360.com)): Harbor, Cosign keyless, digest deploy, Nginx Proxy Manager, Cloudflare edge.

---

## Author

[Barthez Kenwou](https://barthez-kenwou.dev/) — DevSecOps / platform-minded delivery.
