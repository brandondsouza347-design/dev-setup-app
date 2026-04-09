# TunnelBlick GitLab Remote Installation Setup

## Overview

The app is configured to download TunnelBlick from **your GitLab repository** instead of bundling it in the app. This keeps the app size small while ensuring reliable access to TunnelBlick even when public sources are blocked.

---

## Setup Instructions

### Step 1: Upload TunnelBlick to GitLab

You have **two options** for hosting the TunnelBlick .dmg file in GitLab:

#### **Option A: GitLab Package Registry** (Recommended)

1. Navigate to your GitLab project: `https://gitlab.com/<your-username>/dev-setup-app`

2. Go to **Deploy → Package Registry**

3. Upload via GitLab CLI or API:
   ```bash
   # Install GitLab CLI if needed
   brew install glab

   # Upload the package
   curl --header "PRIVATE-TOKEN: <your-token>" \
        --upload-file Tunnelblick_4.0.1_build_5971.dmg \
        "https://gitlab.com/api/v4/projects/<PROJECT_ID>/packages/generic/tunnelblick/4.0.1/Tunnelblick_4.0.1_build_5971.dmg"
   ```

4. Get your PROJECT_ID:
   - Go to: Settings → General → Project ID

#### **Option B: GitLab Release Assets**

1. Create a new release in GitLab: `Deployments → Releases → New Release`

2. Upload `Tunnelblick_4.0.1_build_5971.dmg` as a release asset

3. Note the direct download URL (will be shown after upload)

---

### Step 2: Configure Environment Variables

The installation script checks for these environment variables:

#### **For Package Registry:**
```bash
export SETUP_TUNNELBLICK_REMOTE_URL="https://gitlab.com/api/v4/projects/<PROJECT_ID>/packages/generic/tunnelblick/4.0.1/Tunnelblick_4.0.1_build_5971.dmg"
```

#### **For Release Assets:**
```bash
export SETUP_TUNNELBLICK_REMOTE_URL="https://gitlab.com/<username>/dev-setup-app/-/releases/v2.7.0/downloads/Tunnelblick_4.0.1_build_5971.dmg"
```

#### **For Private Repositories (add authentication):**
```bash
export SETUP_TUNNELBLICK_REMOTE_URL="<your-url-from-above>"
export SETUP_TUNNELBLICK_GITLAB_TOKEN="<your-personal-access-token>"
```

To create a Personal Access Token:
1. GitLab → User Settings → Access Tokens
2. Name: "TunnelBlick Package Download"
3. Scopes: `read_api`, `read_repository`
4. Create token and copy it

---

### Step 3: Configure in DevSetup App

You can set these environment variables in **two ways**:

#### **Option A: Set in User Config (Backend)**

Add to [src-tauri/src/state.rs](../src-tauri/src/state.rs) default config or configuration screen:

```rust
// Future: Add these fields to UserConfig
pub tunnelblick_remote_url: Option<String>,
pub tunnelblick_gitlab_token: Option<String>,
```

#### **Option B: Set at Runtime (Environment)**

The app already reads from environment variables `SETUP_TUNNELBLICK_REMOTE_URL` and `SETUP_TUNNELBLICK_GITLAB_TOKEN`.

Users can set these before running:
```bash
export SETUP_TUNNELBLICK_REMOTE_URL="<gitlab-url>"
export SETUP_TUNNELBLICK_GITLAB_TOKEN="<token>"
./DevSetupApp
```

---

## How It Works

### Installation Priority (Method 0-4)

When a user clicks "Install VPN":

1. **Method 0: Custom/GitLab URL** (if `SETUP_TUNNELBLICK_REMOTE_URL` is set)
   - Downloads from your GitLab
   - Uses token if `SETUP_TUNNELBLICK_GITLAB_TOKEN` is set
   - Falls back to public sources if fails

2. **Method 1: Homebrew** (fastest when available)
   - `brew install --cask tunnelblick`

3. **Method 2: GitHub Releases** (public fallback)
   - Downloads from https://github.com/Tunnelblick/Tunnelblick/releases

4. **Method 3: SourceForge** (alternative mirror)
   - Downloads from https://sourceforge.net/projects/tunnelblick/

5. **Automatic Fallback: OpenVPN CLI** (if all above fail)
   - Installs command-line OpenVPN via Homebrew
   - No GUI, but fully functional

---

## Testing

### Test GitLab Download

```bash
# Set your URL
export SETUP_TUNNELBLICK_REMOTE_URL="https://gitlab.com/api/v4/projects/<ID>/packages/generic/tunnelblick/4.0.1/Tunnelblick_4.0.1_build_5971.dmg"

# Test with curl
curl -I "$SETUP_TUNNELBLICK_REMOTE_URL"

# Should return: HTTP/2 200 OK
```

### Test with Token (Private Repo)

```bash
export SETUP_TUNNELBLICK_GITLAB_TOKEN="your-token-here"

curl -I -H "PRIVATE-TOKEN: $SETUP_TUNNELBLICK_GITLAB_TOKEN" "$SETUP_TUNNELBLICK_REMOTE_URL"
```

### Run Installation Script Directly

```bash
cd dev-setup-app/scripts/macos
export SETUP_TUNNELBLICK_REMOTE_URL="<your-url>"
bash install_tunnelblick_sources.sh
```

You should see:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Method 0/4: Custom Remote URL (GitLab/Hosted)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
→ Downloading from configured URL...
  URL: <your-url>
✓ Download complete
→ Installing from custom source...
✓ Tunnelblick installed successfully from custom URL!
```

---

## File You Need to Upload

**Filename:** `Tunnelblick_4.0.1_build_5971.dmg`
**Version:** 4.0.1 build 5971
**Source:** You provided this file (attached in chat)

**Where to get it if you need to re-download:**
- Official: https://tunnelblick.net/downloads.html
- Direct: https://github.com/Tunnelblick/Tunnelblick/releases

---

## Benefits of This Approach

✅ **App stays small** - No 10-20MB embedded installer
✅ **Network flexibility** - Works even when public sources blocked
✅ **Private control** - Host on your own GitLab
✅ **Version control** - Update TunnelBlick independently of app
✅ **Fallback chain** - 5 different installation methods
✅ **Future-proof** - Already configured for GitLab migration

---

## Migration Checklist

- [ ] Upload `Tunnelblick_4.0.1_build_5971.dmg` to GitLab
- [ ] Get the download URL from GitLab
- [ ] Create personal access token (if private repo)
- [ ] Test download with curl
- [ ] Set `SETUP_TUNNELBLICK_REMOTE_URL` in app config
- [ ] Set `SETUP_TUNNELBLICK_GITLAB_TOKEN` (if needed)
- [ ] Test installation with DevSetup app
- [ ] Document URL for team members

---

## Support

If you encounter issues:

1. **Check URL accessibility:**
   ```bash
   curl -I "$SETUP_TUNNELBLICK_REMOTE_URL"
   ```

2. **Check logs in app** - Activity Logs section shows download progress

3. **Verify token permissions** - Must have `read_api` or `read_repository`

4. **Test manual installation** - Use "Install from File" button as backup

5. **OpenVPN CLI fallback** - Automatically tries if all downloads fail
