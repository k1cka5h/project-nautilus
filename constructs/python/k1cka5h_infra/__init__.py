"""
k1cka5h_infra — Platform-managed CDKTF construct library for Azure.

Import everything from this top-level package:

    from k1cka5h_infra import (
        BaseAzureStack,
        NetworkConstruct, SubnetConfig, SubnetDelegation,
        DatabaseConstruct, PostgresConfig,
        AksConstruct, AksConfig, NodePoolConfig,
    )
"""

from .constructs import (
    BaseAzureStack,
    NetworkConstruct,
    SubnetConfig,
    SubnetDelegation,
    DatabaseConstruct,
    PostgresConfig,
    AksConstruct,
    AksConfig,
    NodePoolConfig,
)

__version__ = "1.4.0"

__all__ = [
    "BaseAzureStack",
    "NetworkConstruct", "SubnetConfig", "SubnetDelegation",
    "DatabaseConstruct", "PostgresConfig",
    "AksConstruct", "AksConfig", "NodePoolConfig",
]
