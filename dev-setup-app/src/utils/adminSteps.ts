// utils/adminSteps.ts — Centralized admin step detection logic

/**
 * List of step IDs that require administrator privileges.
 * These steps must only run when the admin agent is ready.
 *
 * Sourced from: src-tauri/src/admin_agent.rs ADMIN_STEP_IDS
 */
export const ADMIN_STEP_IDS = [
  'enable_wsl',
  'wsl_network',
  'windows_hosts',
  'install_openvpn',
  'revert_wsl_features',
  'revert_windows_hosts',
  'revert_wsl_network',
] as const;

/**
 * Check if any of the provided step IDs require admin privileges.
 *
 * @param stepIds - Array of step IDs to check
 * @returns true if at least one step requires admin, false otherwise
 */
export function hasAdminSteps(stepIds: string[]): boolean {
  return stepIds.some(id => ADMIN_STEP_IDS.includes(id as any));
}

/**
 * Check if a specific step ID requires admin privileges.
 *
 * @param stepId - Step ID to check
 * @returns true if the step requires admin, false otherwise
 */
export function isAdminStep(stepId: string): boolean {
  return ADMIN_STEP_IDS.includes(stepId as any);
}

/**
 * Filter a list of step IDs to only include admin-required steps.
 *
 * @param stepIds - Array of step IDs to filter
 * @returns Array containing only step IDs that require admin
 */
export function getAdminSteps(stepIds: string[]): string[] {
  return stepIds.filter(id => isAdminStep(id));
}

/**
 * Filter a list of step IDs to only include non-admin steps.
 *
 * @param stepIds - Array of step IDs to filter
 * @returns Array containing only step IDs that don't require admin
 */
export function getNonAdminSteps(stepIds: string[]): string[] {
  return stepIds.filter(id => !isAdminStep(id));
}
