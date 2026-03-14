locals {
  # Required tags applied to every resource.
  # Extra tags are merged in, but required keys always win.
  tags = merge(var.extra_tags, {
    managed_by  = "terraform"
    project     = var.project
    environment = var.environment
  })
}
