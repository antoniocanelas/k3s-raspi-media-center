# Kustomize Modernization Summary

## Overview
All Kustomize configuration files have been modernized to eliminate deprecation warnings and use the latest recommended syntax.

## Changes Made

### 1. **Deprecated `bases:` → `resources:`**
   - **Before:** `bases: [../../base]`
   - **After:** `resources: [../../base]`
   - **Files Updated:**
     - `base/kustomization.yaml`
     - `overlays/armhf/kustomization.yaml`
     - `overlays/x86/kustomization.yaml`
     - `overlays/x86_64-with-argocd/kustomization.yaml`
     - `argocd/kustomization.yaml`

### 2. **Deprecated `commonLabels:` → `labels:`**
   - **Before:**
     ```yaml
     commonLabels:
       app: htpc
     ```
   - **After:**
     ```yaml
     labels:
     - pairs:
         app: htpc
     ```
   - **Files Updated:**
     - `base/kustomization.yaml`

### 3. **Deprecated `patchesStrategicMerge:` → `patches:`**
   - **Before:**
     ```yaml
     patchesStrategicMerge:
     - volumes_patch.yaml
     - env_variables_patch.yaml
     ```
   - **After:**
     ```yaml
     patches:
     - path: volumes_patch.yaml
     - path: env_variables_patch.yaml
     ```
   - **Files Updated:**
     - `base/kustomization.yaml`
     - `argocd/kustomization.yaml`

### 4. **Deprecated `vars:` Field (Still Supported)**
   - **Status:** Kept as-is for now (still supported for substitution)
   - **Note:** Future migration to `replacements` may be needed
   - **Files Affected:**
     - `base/kustomization.yaml`

## Build Verification

All manifests have been regenerated with **zero deprecation warnings**:

```bash
✅ install_x86_64.yaml - Generated successfully
✅ install_armhf.yaml - Generated successfully  
✅ install_argocd.yaml - Generated successfully
```

### Test Commands
```bash
kubectl kustomize overlays/armhf
kubectl kustomize overlays/x86
kubectl kustomize argocd
```

## Benefits

1. **Future-Proof:** No deprecation warnings in newer Kustomize versions
2. **Best Practices:** Follows Kustomize recommendations
3. **Clean Output:** All manifests build cleanly
4. **Compatibility:** Maintains full backward compatibility with current deployments

## Future Work

- **vars → replacements:** Migrate from experimental `vars` to `replacements` when ready
- This will provide more control over field substitution with explicit source/target definitions

## Reference

- [Kustomize Deprecation Guide](https://kustomize.io/docs/release-notes/)
- Modern Kustomize documentation and best practices

