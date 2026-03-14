## Summary

<!-- What infrastructure change does this PR make and why? -->

## Environments affected

- [ ] dev
- [ ] staging
- [ ] prod

## Terraform plan reviewed

<!-- The pipeline will post a plan comment. Paste a summary or confirm you have read it. -->

- [ ] I have read the Terraform plan posted by the pipeline
- [ ] The plan contains no unexpected additions, changes, or destructions

## Checklist

- [ ] No secrets are hardcoded in the stack file
- [ ] The `project` and `environment` values have not changed (changing them destroys all resources)
- [ ] Stack synthesizes cleanly locally (`cdktf synth`)
- [ ] Platform team tagged for review if this affects staging or prod (`@k1cka5h/platform-infra`)
