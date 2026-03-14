# Changelog

All notable changes to `myorg/terraform-modules` are documented here.
Versions follow [Semantic Versioning](https://semver.org/).

Breaking changes are announced in **#platform-infra** (Slack) with a migration guide
at least two weeks before the next major release.

---

## [v1.4.0] — 2026-03-13

### Added
- `modules/compute/aks`: `additional_node_pools` now supports `taints` per pool.
- `modules/database/postgres`: `server_configurations` variable for parameter overrides.
- `modules/networking`: `nsg_rules` per-subnet override for custom inbound/outbound rules.

### Changed
- `modules/compute/aks`: system node pool now tainted `CriticalAddonsOnly=true:NoSchedule`
  by default. Workload pods must be placed in additional node pools.

### Fixed
- `modules/networking`: DNS zone VNet link names now handle zone names containing dots.

---

## [v1.3.0] — 2026-01-20

### Added
- `modules/database/postgres`: `geo_redundant_backup` variable.

### Changed
- `modules/compute/aks`: OMS agent is now mandatory (was optional).

---

## [v1.2.0] — 2025-11-05

### Added
- Initial release of `modules/networking`, `modules/database/postgres`,
  and `modules/compute/aks`.
