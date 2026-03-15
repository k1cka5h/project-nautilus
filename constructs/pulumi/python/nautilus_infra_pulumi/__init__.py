"""
nautilus-infra-pulumi
=====================
Platform-managed Pulumi component library for Azure.

Exports:
    NetworkComponent  — VNet, subnets, NSGs, private DNS zones
    DatabaseComponent — PostgreSQL Flexible Server
    AksComponent      — AKS cluster

    SubnetConfig, SubnetDelegation — network config dataclasses
    PostgresConfig                 — database config dataclass
    AksConfig, NodePoolConfig      — AKS config dataclasses

    required_tags — mandatory tag policy helper
"""

from .components import (
    NetworkComponent,
    SubnetConfig,
    SubnetDelegation,
    DatabaseComponent,
    PostgresConfig,
    AksComponent,
    AksConfig,
    NodePoolConfig,
)
from .policy import required_tags

__all__ = [
    "NetworkComponent",
    "SubnetConfig",
    "SubnetDelegation",
    "DatabaseComponent",
    "PostgresConfig",
    "AksComponent",
    "AksConfig",
    "NodePoolConfig",
    "required_tags",
]
