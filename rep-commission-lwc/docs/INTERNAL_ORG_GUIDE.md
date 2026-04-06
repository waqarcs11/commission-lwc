# Internal Org Guide — Commission LWC Project

## Connected Orgs

| Alias | Username | Type | Purpose |
|---|---|---|---|
| `goodman-pbo` | adsknock@gmail.com.pbo | **Dev Hub** | Creates and manages packages |
| `MyCommissionOrg` | adsknock@resourceful-shark-v02x54.com | **Dev Org** (default) | Primary build and test org |
| `CommissionSandbox` | adsknock@gmail.com.pbo.commission | **Sandbox** | goodmangroupllc--commission sandbox |
| `cardiff-datatools` | ryan@goodmangroupllc.co.datatools | Org | Cardiff datatools org |
| `SourceSandbox` | waqar@datatoolspro.com.fcdev | Sandbox | Datatoolspro sandbox |
| `cardiff-dtpfeb` | waqar@datatoolspro.com.co.dtpfeb | Sandbox | Cardiff Feb sandbox |

---

## How to deploy to a specific org

Always run commands from inside the project directory:
```bash
cd E:/xampp/htdocs/commission_LWC/rep-commission-lwc
```

### Deploy to Dev Org (default)
```bash
sf project deploy start --target-org MyCommissionOrg
```

### Deploy to CommissionSandbox
```bash
sf project deploy start --target-org CommissionSandbox
```

### Deploy to any other connected org
```bash
sf project deploy start --target-org <alias>
```

### Deploy a specific folder only (faster)
```bash
sf project deploy start --source-dir force-app/main/default/classes --target-org <alias>
sf project deploy start --source-dir force-app/main/default/lwc --target-org <alias>
```

---

## How to connect a new org

### New sandbox
```bash
sf org login web --alias <NewAlias> --instance-url https://test.salesforce.com
```

### New production org
```bash
sf org login web --alias <NewAlias> --instance-url https://login.salesforce.com
```

### Check all connected orgs
```bash
sf org list
```

---

## How to create a new package version (for distribution)

> Requires the Dev Hub (`goodman-pbo`) to be connected.

**Step 1 — Update version number in `sfdx-project.json`**

Change `versionNumber` (e.g. `1.1.0.NEXT` → `1.2.0.NEXT`) and update `versionDescription`.

**Step 2 — Create the package version with code coverage**
```bash
sf package version create \
  --package "Commission LWC" \
  --installation-key-bypass \
  --code-coverage \
  --wait 20 \
  --target-dev-hub goodman-pbo
```

**Step 3 — Promote to released (required for production installs)**
```bash
sf package version promote --package <VERSION_ID> --target-dev-hub goodman-pbo --no-prompt
```

**Step 4 — Update `docs/POST_INSTALL_GUIDE.md`** with the new version ID and install URL.

---

## Package info

| | |
|---|---|
| **Package Name** | Commission LWC |
| **Package ID** | 0HoPU00000004Ev0AI |
| **Dev Hub** | goodman-pbo |

### Version History

| Version | Version ID | Status |
|---------|------------|--------|
| 1.1.0-2 | 04tPU000002KQzhYAG | Released ✅ |
| 1.1.0-1 | 04tPU000002KC5VYAW | Beta |
| 1.0.0-4 | 04tPU000002JcEvYAK | Released ✅ |

---

## Key rules

- **Never deploy directly to a customer's production org** — always use the package install URL
- **Always run tests** (`--code-coverage`) before promoting a package version
- **Dev Org (`MyCommissionOrg`) is the source of truth** — all changes are built and tested here first
- **Sandbox (`CommissionSandbox`)** is used for UAT/client testing before packaging
