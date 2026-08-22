## What this changes, and why

<!-- One paragraph. If it fixes an issue, link it. -->

## What you measured

<!-- A behaviour claim here is expected to name the run it came from, not
     an expectation. "No change" is a fine answer; "not measured" is fine
     too, as long as it is said. -->

## Checklist

- [ ] `dart analyze` and `dart test` pass in `packages/shelfscan_core`
- [ ] `flutter analyze` and `flutter test` pass in `app`
- [ ] No Flutter or new runtime dependency added to `shelfscan_core`
- [ ] No key, path or photo of anyone's home added to the repository
- [ ] Comments are measurements and non-obvious decisions only
- [ ] If `detectionPromptRules`, `detectionJsonSchema` or the control-set
      fingerprint moved: re-measured at **both** control resolutions, and the
      numbers are in `doc/measurements.md`
      (see CONTRIBUTING.md — these are measured artifacts)
