// utils/settingsMerge.ts — Settings scope inheritance and merge logic

import type { UserConfig } from '../types';

/**
 * Workflow-specific settings structure.
 * Supports overriding global settings or explicitly nullifying them.
 */
export interface WorkflowSettings {
  /** Settings that override global values */
  overrides: Partial<UserConfig>;
  /** Settings that should be explicitly set to null (disabled) */
  nullify: (keyof UserConfig)[];
}

/**
 * Merge global settings with workflow-specific overrides.
 *
 * Merge priority (highest to lowest):
 * 1. Nullified settings → always null
 * 2. Workflow overrides → custom values
 * 3. Global settings → base defaults
 *
 * @param globalSettings - Base settings from Settings page (class scope)
 * @param workflowSettings - Workflow-specific overrides (functional scope)
 * @returns Merged configuration ready for execution
 *
 * @example
 * ```typescript
 * const global = { tenant_name: "erckinetic", git_name: "John" };
 * const workflow = {
 *   overrides: { tenant_name: "prod-client" },
 *   nullify: []
 * };
 * const merged = mergeWorkflowSettings(global, workflow);
 * // Result: { tenant_name: "prod-client", git_name: "John" }
 * ```
 */
export function mergeWorkflowSettings(
  globalSettings: UserConfig,
  workflowSettings?: WorkflowSettings
): UserConfig {
  // If no workflow settings, return global as-is
  if (!workflowSettings) {
    return { ...globalSettings };
  }

  // Start with a copy of global settings as mutable record
  const merged: Record<string, any> = { ...globalSettings };

  // Apply workflow overrides
  Object.entries(workflowSettings.overrides).forEach(([key, value]) => {
    merged[key] = value;
  });

  // Apply nullifications (highest priority)
  workflowSettings.nullify.forEach(key => {
    merged[key] = null;
  });

  return merged as UserConfig;
}

/**
 * Determine if a setting is overridden in the workflow.
 *
 * @returns 'override' | 'nullified' | 'inherited' | 'not-applicable'
 */
export function getSettingSource(
  settingKey: keyof UserConfig,
  workflowSettings?: WorkflowSettings
): 'override' | 'nullified' | 'inherited' | 'not-applicable' {
  if (!workflowSettings) {
    return 'inherited';
  }

  if (workflowSettings.nullify.includes(settingKey)) {
    return 'nullified';
  }

  if (settingKey in workflowSettings.overrides) {
    return 'override';
  }

  return 'inherited';
}

/**
 * Get a summary of workflow settings for display purposes.
 *
 * @returns Counts of overridden, nullified, and inherited settings
 */
export function getWorkflowSettingsSummary(
  requiredSettings: Set<keyof UserConfig>,
  workflowSettings?: WorkflowSettings
): {
  overridden: number;
  nullified: number;
  inherited: number;
  total: number;
} {
  if (!workflowSettings) {
    return {
      overridden: 0,
      nullified: 0,
      inherited: requiredSettings.size,
      total: requiredSettings.size,
    };
  }

  let overridden = 0;
  let nullified = 0;
  let inherited = 0;

  requiredSettings.forEach(setting => {
    const source = getSettingSource(setting, workflowSettings);
    if (source === 'override') overridden++;
    else if (source === 'nullified') nullified++;
    else inherited++;
  });

  return {
    overridden,
    nullified,
    inherited,
    total: requiredSettings.size,
  };
}

/**
 * Create an empty WorkflowSettings structure.
 * Useful for initializing new workflows.
 */
export function createEmptyWorkflowSettings(): WorkflowSettings {
  return {
    overrides: {},
    nullify: [],
  };
}

/**
 * Validate that all required settings have values (either global or override).
 *
 * @returns Array of missing setting keys
 */
export function validateWorkflowSettings(
  globalSettings: UserConfig,
  requiredSettings: Set<keyof UserConfig>,
  workflowSettings?: WorkflowSettings
): (keyof UserConfig)[] {
  const missing: (keyof UserConfig)[] = [];
  const merged = mergeWorkflowSettings(globalSettings, workflowSettings);

  requiredSettings.forEach(setting => {
    const value = merged[setting];
    // Check if value is null, undefined, or empty string
    if (value === null || value === undefined || value === '') {
      missing.push(setting);
    }
  });

  return missing;
}

/**
 * Get display text for a setting's current value and source.
 * Useful for showing inheritance in UI.
 *
 * @example
 * ```typescript
 * getSettingDisplay('tenant_name', global, workflow)
 * // Returns: "prod-client (workflow override)"
 * //       or "erckinetic (global default)"
 * //       or "- (disabled for this workflow)"
 * ```
 */
export function getSettingDisplay(
  settingKey: keyof UserConfig,
  globalSettings: UserConfig,
  workflowSettings?: WorkflowSettings
): { value: string; source: string; } {
  const source = getSettingSource(settingKey, workflowSettings);

  if (source === 'nullified') {
    return {
      value: '-',
      source: 'disabled for this workflow',
    };
  }

  const merged = mergeWorkflowSettings(globalSettings, workflowSettings);
  const value = merged[settingKey];

  // Mask sensitive values
  const isSensitive = settingKey.includes('password') ||
                      settingKey.includes('secret') ||
                      settingKey.includes('token') ||
                      settingKey.includes('pat');

  const displayValue = isSensitive && value
    ? '••••••••'
    : (value?.toString() || '(not set)');

  const sourceLabel = source === 'override'
    ? 'workflow override'
    : 'global default';

  return {
    value: displayValue,
    source: sourceLabel,
  };
}
