# Workflow Settings System - Backend/Frontend Integration Guide

## Overview
This document describes the complete workflow-specific settings system, including frontend implementation (completed) and backend integration requirements (pending implementation).

## Architecture

### Three-Tier Scope Model
The settings system implements an OOP-inspired scope inheritance pattern:

1. **Global Config** (Base/Class scope) - Default UserConfig from settings page
2. **Workflow Overrides** (Instance/Function scope) - Per-workflow customizations
3. **Merged Execution Config** - Runtime configuration combining both

Priority: **Nullify** > **Override** > **Inherit**

### Frontend Components (✅ COMPLETED)

#### 1. Step-to-Settings Mapping (`src/utils/stepSettings.ts`)
- **Purpose**: Maps each of 56 setup steps to required UserConfig fields
- **Exports**:
  - `STEP_SETTINGS_MAP`: Record<string, (keyof UserConfig)[]>
  - `getRequiredSettings(stepIds)`: Returns Set of required settings
  - `groupSettingsByCategory()`: Organizes settings by category
  - `SettingCategory` enum: WSL, Git, Python, Node, Database, Tenant, Network, Workspace
  - `SETTING_LABELS` and `SETTING_DESCRIPTIONS` for UI display

**Example**:
```typescript
STEP_SETTINGS_MAP["gitlab_ssh"] = ["git_name", "git_email", "gitlab_pat", "gitlab_repo_url"]
```

#### 2. Settings Merge Utility (`src/utils/settingsMerge.ts`)
- **Purpose**: Implements inheritance logic for combining global and workflow settings
- **Key Types**:
  ```typescript
  interface WorkflowSettings {
    overrides: Partial<UserConfig>;  // Settings to override
    nullify: (keyof UserConfig)[];   // Settings to disable
  }
  ```
- **Key Functions**:
  - `mergeWorkflowSettings(global, workflow)`: Returns merged UserConfig
  - `getSettingSource(key, workflow)`: Returns 'override' | 'nullified' | 'inherited'
  - `getWorkflowSettingsSummary()`: Count of inherited/overridden/nullified settings
  - `validateWorkflowSettings()`: Find missing required settings
  - `getSettingDisplay()`: Format with sensitive masking

**Merge Logic**:
1. Start with copy of global config
2. Apply workflow overrides
3. Apply nullifications (highest priority - sets to null)

#### 3. WorkflowSettingsEditor Component (`src/components/WorkflowSettingsEditor.tsx`)
- **Purpose**: UI for editing workflow-specific settings
- **Features**:
  - Three-state radio per setting: Inherit | Override | Nullify
  - Shows global value as reference when in Inherit mode
  - Input field appears when Override selected
  - Grouped by category with expand/collapse
  - Real-time summary badge (e.g., "3 overrides")
  - Only shows settings required by selected steps
  - Sensitive fields (password, token, pat) masked

**Props**:
```typescript
{
  stepIds: string[];
  globalConfig: UserConfig;
  workflowSettings: WorkflowSettings;
  onUpdateSettings: (settings: WorkflowSettings) => void;
}
```

#### 4. WorkflowScreen Integration (`src/components/WorkflowScreen.tsx`)
- **Added**: Tabs UI (Steps | Settings)
- **Added**: Settings badge showing override count
- **Added**: Settings tab with WorkflowSettingsEditor
- **Updated**: Save workflow includes settings field
- **Updated**: Edit workflow loads existing settings
- **Updated**: Workflow cards show override count badge

#### 5. CustomWorkflowProgress Display (`src/components/CustomWorkflowProgress.tsx`)
- **Added**: Collapsible "Active Configuration" section in header
- **Shows**: Each setting with source indicator (override/inherited/disabled)
- **Color-coded**: Blue=override, Gray=inherit
- **Badge**: Override count summary

#### 6. Type Definitions (`src/types/index.ts`)
- **Extended**: CustomWorkflow interface
  ```typescript
  interface CustomWorkflow {
    // ... existing fields
    settings?: {
      overrides: Partial<UserConfig>;
      nullify: (keyof UserConfig)[];
    };
  }
  ```

### Backend Implementation (⚠️ PENDING)

#### 1. Rust Type Definitions (✅ COMPLETED in `src-tauri/src/state.rs`)
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowSettings {
    #[serde(default)]
    pub overrides: serde_json::Map<String, serde_json::Value>,
    #[serde(default)]
    pub nullify: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CustomWorkflow {
    // ... existing fields
    #[serde(skip_serializing_if = "Option::is_none")]
    pub settings: Option<WorkflowSettings>,
}
```

#### 2. save_workflow Command (✅ COMPLETED in `src-tauri/src/commands.rs`)
**Signature**:
```rust
#[tauri::command]
pub async fn save_workflow(
    app_handle: AppHandle,
    workflow_id: String,
    name: String,
    description: String,
    step_ids: Vec<String>,
    settings: Option<crate::state::WorkflowSettings>,
) -> Result<(), String>
```

**What it does**:
- Serializes CustomWorkflow with settings field to JSON
- Saves to `{app_data_dir}/workflows/{workflow_id}.json`
- Backward compatible (existing workflows without settings load correctly)

**Frontend Call**:
```typescript
await invoke('save_workflow', {
  workflowId,
  name,
  description,
  stepIds,
  settings: workflowSettings,  // NEW: WorkflowSettings object
});
```

#### 3. start_workflow Command (❌ NOT IMPLEMENTED)
**Required Signature**:
```rust
#[tauri::command]
pub async fn start_workflow(
    app_handle: AppHandle,
    state: State<'_, AppState>,
    workflow_id: String,
    config: UserConfig,  // NEW: Merged config (not global config!)
) -> Result<(), String>
```

**Implementation Requirements**:
1. Load workflow from file
2. Validate all required steps exist
3. Execute steps in workflow.step_ids order
4. **Use provided `config` parameter** (already merged on frontend) instead of loading global config
5. Pass config fields to step scripts via environment variables
6. Emit progress events (step_started, step_progress, step_completed)
7. Update workflow.last_run_at timestamp

**Frontend Call** (from `src/hooks/useSetup.ts`):
```typescript
// In executeWorkflow function:
import { mergeWorkflowSettings } from '../utils/settingsMerge';

const mergedConfig = mergeWorkflowSettings(config, workflow.settings);

await invoke('start_workflow', {
  workflowId: workflow.id,
  config: mergedConfig,  // Pass merged config (not global!)
});
```

**Critical ENV Variable Mapping**:
Backend must set ALL UserConfig fields as environment variables for scripts:
```rust
// Example environment variable mapping:
"SETUP_TENANT_NAME" => config.tenant_name
"SETUP_GIT_NAME" => config.git_name
"SETUP_GIT_EMAIL" => config.git_email
"SETUP_GITLAB_PAT" => config.gitlab_pat
"SETUP_WSL_DISTRO_NAME" => config.wsl_distro_name
// ... etc for all ~30 UserConfig fields
```

These environment variables are read by PowerShell/Bash scripts in:
- `scripts/windows/*.ps1`
- `scripts/windows/*.sh`
- `scripts/macos/*.sh`

#### 4. Environment Variable Propagation (⚠️ VERIFY EXISTING)
The orchestrator needs to ensure ALL config fields are available as env vars.

**Check in `src-tauri/src/orchestrator.rs`**:
- Does `run_step()` or similar function set env vars?
- Are ALL UserConfig fields mapped to env var names?
- Do nullified settings get passed as empty string or not set at all?

**Example Missing Field Scenario**:
```typescript
// User overrides tenant_name for workflow
workflowSettings.overrides.tenant_name = "erckinetic-dev"

// Backend merges: mergedConfig.tenant_name = "erckinetic-dev"
// Backend MUST set: env["SETUP_TENANT_NAME"] = "erckinetic-dev"
// Script reads: $env:SETUP_TENANT_NAME (PowerShell) or $SETUP_TENANT_NAME (Bash)
```

### Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User Creates Workflow                                        │
│    - Selects steps                                              │
│    - Clicks Settings tab                                        │
│    - Overrides tenant_name = "erckinetic-dev"                  │
│    - Nullifies openvpn_config_file                             │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Save Workflow (Frontend → Backend)                           │
│    invoke('save_workflow', {                                    │
│      workflowId: "wf_123456",                                   │
│      name: "Dev Setup",                                         │
│      stepIds: ["copy_tenant", "gitlab_ssh"],                    │
│      settings: {                                                │
│        overrides: { tenant_name: "erckinetic-dev" },           │
│        nullify: ["openvpn_config_file"]                        │
│      }                                                           │
│    })                                                            │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Backend Saves JSON                                            │
│    {                                                             │
│      "id": "wf_123456",                                         │
│      "name": "Dev Setup",                                       │
│      "step_ids": ["copy_tenant", "gitlab_ssh"],                 │
│      "settings": {                                               │
│        "overrides": { "tenant_name": "erckinetic-dev" },       │
│        "nullify": ["openvpn_config_file"]                      │
│      }                                                           │
│    }                                                             │
└─────────────────────────────────────────────────────────────────┘
                 │
                 │ (Later: User clicks Run)
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Execute Workflow (Frontend Prepares)                         │
│    globalConfig = { tenant_name: "erckinetic", ... }           │
│    workflow.settings = { overrides: {...}, nullify: [...] }    │
│                                                                  │
│    mergedConfig = mergeWorkflowSettings(globalConfig, workflow) │
│    // Result:                                                    │
│    // {                                                          │
│    //   tenant_name: "erckinetic-dev",  ← OVERRIDDEN           │
│    //   openvpn_config_file: null,       ← NULLIFIED            │
│    //   git_name: "Brandon",             ← INHERITED            │
│    // }                                                          │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Backend Executes (❌ NOT IMPLEMENTED)                        │
│    invoke('start_workflow', {                                   │
│      workflowId: "wf_123456",                                   │
│      config: mergedConfig   ← ENTIRE MERGED CONFIG              │
│    })                                                            │
│                                                                  │
│    Backend should:                                               │
│    - Load workflow from file                                     │
│    - Use provided `config` param (NOT global config)            │
│    - Set env vars for EACH config field                         │
│    - Execute steps in order                                      │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Script Execution                                              │
│    # PowerShell script: copy_tenant.sh                          │
│    $tenant = $env:SETUP_TENANT_NAME   ← "erckinetic-dev"       │
│    Copy-Item "tenant_template" -Destination $tenant             │
│                                                                  │
│    # Bash script: gitlab_ssh.sh                                 │
│    TENANT_NAME=$SETUP_TENANT_NAME      ← "erckinetic-dev"      │
│    git clone git@gitlab:$TENANT_NAME                            │
└─────────────────────────────────────────────────────────────────┘
```

## Testing Checklist

### Frontend Testing (✅ Ready for Testing)
- [ ] Create new workflow with steps
- [ ] Switch to Settings tab
- [ ] Override a setting (e.g., tenant_name)
- [ ] Verify setting shows in override mode with input field
- [ ] Nullify a setting
- [ ] Save workflow
- [ ] Verify saved workflow shows override badge
- [ ] Edit workflow and verify settings load correctly
- [ ] Run workflow and verify active config display
- [ ] Collapse/expand config section

### Backend Testing (❌ Blocked - Awaiting Implementation)
- [ ] Load existing workflow with settings
- [ ] Verify settings field deserializes correctly
- [ ] Execute workflow with overrides
- [ ] Verify merged config is used (not global)
- [ ] Verify scripts receive correct env variables
- [ ] Test with nullified settings (should be null/empty)
- [ ] Test backward compatibility (old workflows without settings)

## Migration Guide

### For Existing Workflows
Workflows created before this feature will load with `settings: undefined` which is handled gracefully:
- Frontend: Treats as empty settings (all inherited)
- Backend: Serializes without settings field (`skip_serializing_if`)
- Scripts: Receive global config (same as before)

### Adding New Settings
To add a new UserConfig field that workflows can override:

1. Add to UserConfig type (`src/types/index.ts`)
2. Add to SETTING_LABELS in `stepSettings.ts`
3. Add to SETTING_DESCRIPTIONS
4. Add to appropriate step mappings in STEP_SETTINGS_MAP
5. Add to category mapping in groupSettingsByCategory
6. Update backend to propagate as environment variable

## Known Limitations

1. **start_workflow command not implemented** - Frontend is ready but backend execution incomplete
2. **No validation on backend** - Should verify required settings aren't nullified
3. **No conflict detection** - Could warn if user nullifies a setting required by selected steps
4. **No setting templates** - Future: "Common presets" for workflows
5. **No setting inheritance UI indicator on edit** - Could show which global value will be inherited

## Next Steps (Priority Order)

1. **[CRITICAL]** Implement `start_workflow` Tauri command
   - Accept merged UserConfig parameter
   - Execute workflow steps with provided config
   - DO NOT reload global config from file

2. **[HIGH]** Verify environment variable propagation in orchestrator
   - Map all UserConfig fields to env vars
   - Handle nullified settings (empty string vs unset)

3. **[MEDIUM]** Add backend validation
   - Check required settings aren't nullified
   - Validate override values match expected types

4. **[LOW]** Frontend enhancements
   - Setting templates/presets
   - Conflict warnings
   - Bulk override UI

## Files Changed

### Frontend
- `src/types/index.ts` - Extended CustomWorkflow
- `src/utils/stepSettings.ts` - NEW: Step-to-settings mapping
- `src/utils/settingsMerge.ts` - NEW: Settings inheritance logic
- `src/components/WorkflowSettingsEditor.tsx` - NEW: Settings editor UI
- `src/components/WorkflowScreen.tsx` - Added tabs, settings integration
- `src/components/CustomWorkflowProgress.tsx` - Added config display
- `src/hooks/useSetup.ts` - Updated executeWorkflow (commented merge logic)
- `src/App.tsx` - Pass config to WorkflowScreen and CustomWorkflowProgress

### Backend
- `src-tauri/src/state.rs` - Added WorkflowSettings struct
- `src-tauri/src/commands.rs` - Updated save_workflow signature
- **[MISSING]** `src-tauri/src/commands.rs` - start_workflow implementation
- **[VERIFY]** `src-tauri/src/orchestrator.rs` - Environment variable mapping

## Summary

The frontend is fully implemented and ready for testing. The backend has partial support (save/load workflows with settings) but needs the critical `start_workflow` command implementation to complete the integration. The key requirement is ensuring the backend uses the merged config passed from the frontend rather than reloading global config from disk.

**The user's request to "make sure the backend ties nicely to the frontend" means**:
1. Backend must accept merged UserConfig from frontend (not derive it)
2. All config fields must flow through to environment variables
3. No silent failures if settings are missing/nullified
4. Backward compatibility with workflows created before this feature
