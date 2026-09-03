# PesenHub

PesenHub adalah monorepo dengan satu histori Git dan dua komponen aplikasi:

```text
.
├── .github/        # Issue/PR template dan workflow CI/CD
├── docs/           # Panduan konfigurasi repository
├── pesenhub_be/    # Backend Golang, PostgreSQL, WAHA, dan Web Customer
├── pesenhub_app/   # Flutter POS/KDS
├── CONTRIBUTING.md
├── PRD.md
└── MEMORY.md
```

- [Backend](pesenhub_be/README.md)
- [Mobile](pesenhub_app/README.md)
- [Aturan kontribusi](CONTRIBUTING.md)
- [Setup GitHub dan branch protection](docs/GITHUB_SETUP.md)
- [Environment development dan secret matrix](docs/ENVIRONMENT.md)
- [Roadmap produk dan mapping Phase #2–#8](PRD.md#12-roadmap-implementasi-berbasis-phase)
- [Phase 0 closing evidence](docs/PHASE_0_CLOSING_EVIDENCE.md)
- [HTTP API conventions](docs/API_CONVENTIONS.md)
- [OpenAPI contract](docs/api/openapi.yaml)
- [Core domain model dan ERD](docs/CORE_DOMAIN_MODEL.md)
- [Customer identity dan privacy](docs/CUSTOMER_IDENTITY.md)
- [Menu catalog contract](docs/MENU_CATALOG.md)

## Backend

```bash
cd pesenhub_be
./run.sh setup
./run.sh dev
./run.sh status
./run.sh health
```

Panduan operasional lengkap tersedia di [`pesenhub_be/ATURAN.md`](pesenhub_be/ATURAN.md).

## Kontribusi dan CI/CD

Semua perubahan mengikuti:

```text
Issue → Branch → Pull Request → Review → Merge
```

Pull Request ke `main` diperiksa oleh Contribution Policy, Backend CI, dan Mobile CI. CI Backend dan Mobile terpisah dan tetap melaporkan status sukses ketika komponennya tidak berubah. Backend CD memublikasikan image multi-stage ke GHCR pada push `main` atau tag `backend-v*`. Mobile CD membangun APK release sebagai artifact 14 hari pada push `main` atau tag `mobile-v*`; APK belum production-signed dan tidak diunggah ke Play Store.

Badge sengaja belum ditambahkan sampai kebijakan badge dan workflow default disepakati melalui Issue.
