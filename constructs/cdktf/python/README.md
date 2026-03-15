# nautilus-infra — Python

Platform-managed CDKTF construct library for Azure. Published to the internal
PyPI registry at `https://pkgs.nautilus.internal/simple`.

## Install

```bash
pip install nautilus-infra==1.4.0 --index-url https://pkgs.nautilus.internal/simple
```

## Constructs

| Class | Wraps | Key outputs |
|-------|-------|-------------|
| `BaseAzureStack` | Provider + AzureRM state backend | — |
| `NetworkConstruct` | `modules/networking` | `vnet_id`, `subnet_ids`, `dns_zone_ids` |
| `DatabaseConstruct` | `modules/database/postgres` | `fqdn`, `server_id` |
| `AksConstruct` | `modules/compute/aks` | `cluster_id`, `kubelet_identity_object_id` |

## Development

```bash
pip install -e ".[dev]"
pytest tests/ -v
```

## Publishing

```bash
python -m build
twine upload --repository-url https://pkgs.nautilus.internal dist/*
```
