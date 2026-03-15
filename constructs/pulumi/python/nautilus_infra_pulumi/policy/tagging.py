"""
Required tagging policy
=======================
Injects mandatory tags onto every Azure resource.
Developers never call this directly — components call it automatically.
"""

from typing import Optional


def required_tags(project: str, environment: str, extra: Optional[dict] = None) -> dict:
    """Return the mandatory tag set for all Azure resources.

    Required tags always win — extra keys are merged underneath them.
    """
    tags: dict = {
        "managed_by":  "pulumi",
        "project":     project,
        "environment": environment,
    }
    if extra:
        return {**extra, **tags}
    return tags
