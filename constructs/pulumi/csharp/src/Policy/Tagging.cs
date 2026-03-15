namespace Nautilus.Infra.Pulumi.Policy;

/// <summary>
/// Required tagging policy.
/// Injects mandatory tags onto every Azure resource.
/// Developers never call this directly — components call it automatically.
/// </summary>
public static class Tagging
{
    public static Dictionary<string, string> RequiredTags(
        string project,
        string environment,
        Dictionary<string, string>? extra = null)
    {
        var tags = new Dictionary<string, string>(extra ?? [])
        {
            // Required tags always win — overwrite any matching key from extra.
            ["managed_by"]  = "pulumi",
            ["project"]     = project,
            ["environment"] = environment,
        };
        return tags;
    }
}
