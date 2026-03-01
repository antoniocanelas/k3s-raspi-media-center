# GitHub Setup & Push Instructions

## Repository Information

- **Repository**: https://github.com/antoniocanelas/htk8s
- **Branch**: `canelas` (current working branch)
- **Argo CD Application**: `htpc-stack` in `argocd` namespace

---

## Prerequisites

### 1. Create GitHub Repository

If you haven't already created the repository:

1. Go to https://github.com/new
2. Create repository named `htk8s`
3. **Do NOT** initialize with README (we already have one)
4. Click "Create repository"

### 2. GitHub Authentication

Choose one method:

**Option A: SSH (Recommended)**
```bash
# Generate SSH key (if you don't have one)
ssh-keygen -t ed25519 -C "your-email@example.com"

# Add to GitHub: Settings → SSH and GPG keys → New SSH key
# Paste public key from ~/.ssh/id_ed25519.pub
```

**Option B: HTTPS with Personal Access Token**
```bash
# Create token at: Settings → Developer settings → Personal access tokens
# Store it securely (you'll use it as password when pushing)
```

---

## Push to GitHub

### First Time Push

```bash
# Navigate to project
cd /Users/ctw00293/other-projects/htk8s

# Set upstream and push (using SSH)
git push -u origin canelas

# Or using HTTPS (will prompt for token)
git push -u origin canelas
```

### Verify Push

```bash
# Check remote tracking
git branch -vv

# Should show:
# canelas c3a3758 [origin/canelas] feat: modernize Kustomize...
```

---

## GitOps Workflow Setup

Once pushed to GitHub, enable auto-sync in Argo CD:

### 1. Update Argo CD Application

The `htpc-stack` Application is already configured to point to your repo. Deploy it:

```bash
kubectl apply -f install_argocd.yaml
```

### 2. Verify Application Status

```bash
kubectl -n argocd get applications
kubectl -n argocd describe application htpc-stack
```

### 3. Access Argo CD UI

```bash
# Get Argo CD password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access at: http://YOUR_IP/argocd/
# Username: admin
# Password: <from above>
```

### 4. Enable Auto-Sync

In Argo CD UI:
- Click on `htpc-stack` Application
- Click "Sync" → "Synchronize"
- Check "Auto-sync" in Application details
- All changes in Git will now auto-deploy

---

## Typical GitOps Workflow

### Making Changes

1. **Make changes locally**
   ```bash
   vim overlays/armhf/kustomization.yaml
   ```

2. **Test locally**
   ```bash
   kubectl kustomize overlays/armhf > test.yaml
   kubectl apply -f test.yaml --dry-run=client
   ```

3. **Commit to Git**
   ```bash
   git add .
   git commit -m "feat: update Radarr image to arm64v8-4.0.0"
   ```

4. **Push to GitHub**
   ```bash
   git push origin canelas
   ```

5. **Argo CD syncs automatically** (if auto-sync enabled)
   ```bash
   # Watch sync progress
   kubectl -n argocd get applications -w
   ```

---

## Branch Strategy

### Current Setup

- **canelas** - Your working/deployment branch
- **main** (optional) - Stable release branch

### Recommended Workflow

For larger changes, use feature branches:

```bash
# Create feature branch
git checkout -b feat/update-jellyfin-image

# Make changes and commit
git add .
git commit -m "feat: update Jellyfin to v10.12.0"

# Push feature branch
git push origin feat/update-jellyfin-image

# Create Pull Request on GitHub (optional for personal projects)
# Merge to canelas once tested
git checkout canelas
git pull origin canelas
git merge feat/update-jellyfin-image
git push origin canelas
```

---

## Troubleshooting

### Push Rejected

**Error**: `fatal: The remote end hung up unexpectedly`

**Solution**:
```bash
# Check remote URL
git remote -v

# Verify SSH key or token is set up correctly
# If SSH, test connection:
ssh -T git@github.com

# If HTTPS, ensure token has repo:full access
```

### Argo CD Not Syncing

**Check Application status**:
```bash
kubectl -n argocd describe application htpc-stack

# Look for:
# - Sync Status: Synced/OutOfSync
# - Health Status: Healthy/Degraded
# - Conditions and messages for issues
```

**Force re-sync**:
```bash
kubectl -n argocd patch app htpc-stack -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type merge
```

---

## GitHub Repository Settings (Optional)

### Recommended Settings

1. **Settings → General**
   - Description: "Home Theater PC Stack on Kubernetes"
   - Default branch: `canelas`

2. **Settings → Branches**
   - Add branch protection rule for `canelas`
   - Require pull request reviews (optional)

3. **Settings → Webhooks**
   - Argo CD will pull from GitHub automatically
   - No special webhook needed for read-only access

---

## Continuous Deployment Pipeline

```
Your Local Machine
        ↓
    git push
        ↓
   GitHub (htk8s repo)
        ↓
  Argo CD watches repo
        ↓
  Detects changes (every 3 min by default)
        ↓
  kubectl apply -f manifests
        ↓
   Kubernetes Cluster
        ↓
   htpc namespace updated
```

---

## Quick Commands Reference

```bash
# View commit history
git log --oneline

# Check what will be pushed
git log origin/canelas..canelas

# Push all commits
git push origin canelas

# Pull latest from GitHub
git pull origin canelas

# Check Argo CD sync status
kubectl -n argocd get applications

# View Argo CD logs
kubectl -n argocd logs deploy/argocd-controller
```

---

## Next Steps

1. ✅ Create GitHub repo if needed
2. ✅ Set up GitHub authentication (SSH or token)
3. ✅ Push current code: `git push -u origin canelas`
4. ✅ Deploy Argo CD with updated Application: `kubectl apply -f install_argocd.yaml`
5. ✅ Enable auto-sync in Argo CD UI
6. 🎉 **Start committing changes and watching them auto-deploy!**

---

## Support

For issues, check:
- Argo CD logs: `kubectl -n argocd logs -f deploy/argocd-controller`
- Application status: `kubectl -n argocd describe app htpc-stack`
- Git status: `git status` and `git log`

