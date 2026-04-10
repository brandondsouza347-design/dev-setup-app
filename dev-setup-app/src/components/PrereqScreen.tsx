// components/PrereqScreen.tsx — Pre-flight checks before setup
import React, { useEffect } from 'react';
import { CheckCircle, XCircle, RefreshCw, ChevronRight, ChevronLeft, ShieldCheck, ShieldAlert, Loader2, AlertTriangle, Play, FolderOpen, ScrollText, ChevronDown, ChevronUp, Trash2, StopCircle } from 'lucide-react';
import { open as openDialog } from '@tauri-apps/plugin-dialog';
import type { PrereqCheck, WizardPage, AdminAgentStatus, UserConfig, LogEntry } from '../types';

const LOG_COLORS: Record<string, string> = {
  info:    'text-gray-300',
  warn:    'text-yellow-400',
  error:   'text-red-400',
  success: 'text-green-400',
};

interface Props {
  checks: PrereqCheck[];
  onCheck: () => Promise<void>;
  onNext: (page: WizardPage) => void;
  onBack: () => void;
  isWindows: boolean;
  adminAgentStatus: AdminAgentStatus;
  adminAgentError: string | null;
  adminAgentLogs: string[];
  onRequestAdminAgent: () => Promise<void>;
  onShutdownAdminAgent: () => Promise<void>;
  onPrereqAction?: (actionId: string) => Promise<void>;
  config: UserConfig;
  onUpdateConfig: (key: keyof UserConfig, value: string) => void;
  onSaveConfig: (cfg: UserConfig) => Promise<void>;
  prereqLogs: LogEntry[];
  onClearPrereqLogs: () => void;
}

export const PrereqScreen: React.FC<Props> = ({
  checks,
  onCheck,
  onNext,
  onBack,
  isWindows,
  adminAgentStatus,
  adminAgentError,
  adminAgentLogs,
  onRequestAdminAgent,
  onShutdownAdminAgent,
  onPrereqAction,
  config,
  onUpdateConfig,
  onSaveConfig,
  prereqLogs,
  onClearPrereqLogs,
}) => {
  const [checking, setChecking] = React.useState(false);
  const [runningAction, setRunningAction] = React.useState<string | null>(null);
  const [logsExpanded, setLogsExpanded] = React.useState(true);

  useEffect(() => {
    runChecks();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const runChecks = async () => {
    setChecking(true);
    try {
      await onCheck();
    } finally {
      setChecking(false);
    }
  };

  const handleAction = async (actionId: string) => {
    if (!onPrereqAction) return;
    setRunningAction(actionId);
    try {
      await onPrereqAction(actionId);
      // Re-run checks after action completes
      await runChecks();
    } catch (error) {
      console.error('Prereq action failed:', error);
    } finally {
      setRunningAction(null);
    }
  };

  const browseVpn = async () => {
    const selected = await openDialog({
      directory: false,
      multiple: false,
      filters: [
        { name: 'OpenVPN Config', extensions: ['ovpn', 'conf'] },
      ],
    });
    if (selected) {
      // Reset running action if user changes file while VPN is connecting
      if (runningAction === 'connect_vpn') {
        setRunningAction(null);
      }
      onUpdateConfig('openvpn_config_path', selected);
      // Save the config so it's persisted and available to scripts
      const updatedConfig = { ...config, openvpn_config_path: selected };
      await onSaveConfig(updatedConfig);
    }
  };

  const browseTunnelblickInstaller = async () => {
    const selected = await openDialog({
      directory: false,
      multiple: false,
      filters: [
        { name: 'Tunnelblick Installer', extensions: ['dmg', 'pkg'] },
      ],
    });
    if (selected) {
      onUpdateConfig('tunnelblick_installer_path', selected);
      // Save the config so it's persisted and available to scripts
      const updatedConfig = { ...config, tunnelblick_installer_path: selected };
      await onSaveConfig(updatedConfig);
    }
  };

  const getActionButtonLabel = (actionId: string): string => {
    switch (actionId) {
      case 'install_openvpn':
        return isWindows ? 'Install OpenVPN' : 'Install Tunnelblick';
      case 'install_xcode_clt':
        return 'Install Xcode CLT';
      case 'install_homebrew':
        return 'Install Homebrew';
      case 'connect_vpn':
        return 'Connect to VPN';
      default:
        return 'Install';
    }
  };

  const isActionDisabled = (actionId: string): { disabled: boolean; reason?: string } => {
    // Tunnelblick requires Homebrew on macOS
    if (actionId === 'install_openvpn' && !isWindows) {
      const homebrewCheck = checks.find(c => c.name === 'Homebrew');
      if (!homebrewCheck?.passed) {
        return { disabled: true, reason: 'Install Homebrew first' };
      }
    }

    // Homebrew requires Xcode CLT on macOS
    if (actionId === 'install_homebrew' && !isWindows) {
      const xcodeCheck = checks.find(c => c.name === 'Xcode Command Line Tools');
      if (!xcodeCheck?.passed) {
        return { disabled: true, reason: 'Install Xcode CLT first' };
      }
    }

    return { disabled: false };
  };

  const allPassed = checks.length > 0 && checks.every((c) => c.passed || c.warning);
  const hasFailures = checks.some((c) => !c.passed && !c.warning);

  // Group VPN-related checks together (handle both Windows and macOS)
  const openvpnCheck = checks.find(c =>
    c.name === 'OpenVPN (VPN Client)' || c.name.startsWith('VPN Client (')
  );
  const vpnConnectionCheck = checks.find(c => c.name === 'VPN Connection Status');
  const vpnConnCheck = checks.find(c => c.name === 'GitLab VPN Connectivity');
  const otherChecks = checks.filter(c =>
    c.name !== 'OpenVPN (VPN Client)' &&
    !c.name.startsWith('VPN Client (') &&
    c.name !== 'VPN Connection Status' &&
    c.name !== 'GitLab VPN Connectivity'
  );

  return (
    <div className="flex flex-col h-full p-8">
      <div className="mb-6">
        <button onClick={onBack} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 mb-4">
          <ChevronLeft className="w-4 h-4" /> Back
        </button>
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white">Pre-flight Checks</h2>
        <p className="text-gray-500 dark:text-gray-400 mt-1">
          Verifying your system is ready before starting the setup.
        </p>
      </div>

      {/* Admin Agent card — Windows only */}
      {isWindows && (
        <div className={`mb-4 p-4 rounded-lg border ${
          adminAgentStatus === 'ready'
            ? 'bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800'
            : adminAgentStatus === 'error'
            ? 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800'
            : adminAgentStatus === 'requesting'
            ? 'bg-blue-50 dark:bg-blue-900/20 border-blue-200 dark:border-blue-800'
            : 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800'
        }`}>
          <div className="flex items-start gap-3">
            {adminAgentStatus === 'ready' && <ShieldCheck className="w-5 h-5 text-green-500 mt-0.5 shrink-0" />}
            {adminAgentStatus === 'error'  && <ShieldAlert className="w-5 h-5 text-red-500 mt-0.5 shrink-0" />}
            {adminAgentStatus === 'requesting' && <Loader2 className="w-5 h-5 text-blue-500 mt-0.5 shrink-0 animate-spin" />}
            {adminAgentStatus === 'idle'   && <XCircle className="w-5 h-5 text-red-500 mt-0.5 shrink-0" />}
            <div className="flex-1 min-w-0">
              <div className="font-medium text-gray-900 dark:text-white">Admin Privileges for WSL Steps</div>
              {adminAgentStatus === 'idle' && (
                <p className="text-sm text-red-700 dark:text-red-300 mt-1">
                  Not running as Administrator — 6 WSL-related steps require elevation.
                  Click below to open the standard Windows UAC prompt for <strong>powershell.exe</strong>.
                </p>
              )}
              {adminAgentStatus === 'requesting' && (
                <p className="text-sm text-blue-700 dark:text-blue-300 mt-1">
                  Waiting for the elevation dialog… Enter your password in the <strong>Elevate Trusted</strong> popup, then wait for this to turn green.
                </p>
              )}
              {adminAgentStatus === 'ready' && (
                <p className="text-sm text-green-700 dark:text-green-300 mt-1">
                  Admin steps enabled — WSL enablement, network config, and hosts file steps will run elevated automatically.
                </p>
              )}
              {adminAgentStatus === 'error' && (
                <pre className="text-xs text-red-700 dark:text-red-300 mt-1 whitespace-pre-wrap break-words max-h-40 overflow-y-auto font-mono bg-red-100 dark:bg-red-900/30 rounded p-2">
                  {adminAgentError ?? 'Failed to connect to the admin agent.'}
                </pre>
              )}
              {/* Live progress log — shown while requesting or on error */}
              {(adminAgentStatus === 'requesting' || adminAgentStatus === 'error') && adminAgentLogs.length > 0 && (
                <div className="mt-2 max-h-32 overflow-y-auto rounded bg-black/5 dark:bg-white/5 p-2">
                  {adminAgentLogs.map((line, i) => (
                    <div key={i} className="text-xs font-mono text-gray-700 dark:text-gray-300 leading-5">{line}</div>
                  ))}
                </div>
              )}
            </div>
            <div className="shrink-0">
              {adminAgentStatus === 'idle' && (
                <button
                  onClick={onRequestAdminAgent}
                  className="px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg transition-colors"
                >
                  Enable Admin Steps
                </button>
              )}
              {adminAgentStatus === 'requesting' && (
                <span className="text-sm text-blue-600 dark:text-blue-400 font-medium">Connecting…</span>
              )}
              {adminAgentStatus === 'ready' && (
                <button
                  onClick={onShutdownAdminAgent}
                  className="px-3 py-1.5 text-sm border border-green-400 text-green-700 dark:text-green-300 hover:bg-green-100 dark:hover:bg-green-900/40 rounded-lg transition-colors"
                >
                  Disconnect
                </button>
              )}
              {adminAgentStatus === 'error' && (
                <button
                  onClick={onRequestAdminAgent}
                  className="px-3 py-1.5 text-sm bg-red-600 hover:bg-red-700 text-white font-medium rounded-lg transition-colors"
                >
                  Retry
                </button>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Check results */}
      <div className="flex-1 space-y-3">
        {checking && checks.length === 0 && (
          <div className="flex items-center gap-3 text-gray-500">
            <RefreshCw className="w-5 h-5 animate-spin" />
            Running checks…
          </div>
        )}

        {/* Combined VPN Card - OpenVPN Installation + Connection Status + Connectivity */}
        {(openvpnCheck || vpnConnectionCheck || vpnConnCheck) && (
          <div className={`p-4 rounded-lg border ${
            openvpnCheck?.passed && vpnConnectionCheck?.passed && vpnConnCheck?.passed
              ? 'bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800'
              : !openvpnCheck?.passed && openvpnCheck?.actionable
              ? 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800'
              : 'bg-amber-50 dark:bg-amber-900/20 border-amber-200 dark:border-amber-700'
          }`}>
            <div className="flex items-start gap-3">
              {openvpnCheck?.passed && (!vpnConnectionCheck || vpnConnectionCheck?.passed) && vpnConnCheck?.passed ? (
                <CheckCircle className="w-5 h-5 text-green-500 mt-0.5 shrink-0" />
              ) : !openvpnCheck?.passed ? (
                <XCircle className="w-5 h-5 text-red-500 mt-0.5 shrink-0" />
              ) : (
                <AlertTriangle className="w-5 h-5 text-amber-500 mt-0.5 shrink-0" />
              )}
              <div className="flex-1 min-w-0">
                <div className="font-medium text-gray-900 dark:text-white">VPN Access</div>
                {openvpnCheck && !openvpnCheck.passed && (
                  <p className="text-xs text-red-600 dark:text-red-400 mt-1 font-medium">
                    ⚠ Admin rights required for OpenVPN installation
                  </p>
                )}
                <div className="mt-2 space-y-3">
                  {/* VPN Client Installation Status */}
                  {openvpnCheck && (
                    <div className="flex items-start gap-2">
                      {openvpnCheck.passed ? (
                        <CheckCircle className="w-4 h-4 text-green-500 mt-0.5 shrink-0" />
                      ) : (
                        <XCircle className="w-4 h-4 text-red-500 mt-0.5 shrink-0" />
                      )}
                      <div className="flex-1">
                        <div className="text-sm">
                          <span className="font-medium text-gray-900 dark:text-white">VPN Client: </span>
                          <span className="text-gray-600 dark:text-gray-400">{openvpnCheck.message}</span>
                          {!isWindows && config.vpn_method && openvpnCheck.passed && (
                            <span className="ml-2 px-2 py-0.5 text-xs font-medium bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300 rounded">
                              {config.vpn_method === 'tunnelblick' ? 'Tunnelblick (GUI)' : 'OpenVPN CLI'}
                            </span>
                          )}
                        </div>
                        {/* Install buttons and file picker */}
                        {openvpnCheck.actionable && openvpnCheck.action_id && !openvpnCheck.passed && (() => {
                          const actionState = isActionDisabled(openvpnCheck.action_id!);
                          const isDisabled = runningAction !== null || actionState.disabled;

                          return (
                            <div className="mt-2 flex flex-col gap-2">
                              <div className="flex gap-2">
                                <button
                                  onClick={() => handleAction(openvpnCheck.action_id!)}
                                  disabled={isDisabled}
                                  className="flex items-center gap-1.5 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed text-white font-medium rounded-lg transition-colors"
                                >
                                  {runningAction === openvpnCheck.action_id ? (
                                    <Loader2 className="w-4 h-4 animate-spin" />
                                  ) : (
                                    <Play className="w-4 h-4" />
                                  )}
                                  {isWindows ? 'Install OpenVPN' : 'Install VPN'}
                                </button>
                                {/* Manual install from file (macOS only) */}
                                {!isWindows && (
                                  <button
                                    onClick={async () => {
                                      await browseTunnelblickInstaller();
                                      if (config.tunnelblick_installer_path) {
                                        await handleAction('install_tunnelblick_manual');
                                      }
                                    }}
                                    disabled={runningAction !== null}
                                    className="flex items-center gap-1.5 px-3 py-1.5 text-sm bg-green-600 hover:bg-green-700 disabled:bg-gray-400 disabled:cursor-not-allowed text-white font-medium rounded-lg transition-colors"
                                    title="Install Tunnelblick from a local .dmg or .pkg file"
                                  >
                                    <FolderOpen className="w-4 h-4" />
                                    Install from File
                                  </button>
                                )}
                              </div>
                              {actionState.disabled && actionState.reason && (
                                <span className="text-xs text-amber-600 dark:text-amber-400">
                                  {actionState.reason}
                                </span>
                              )}
                            </div>
                          );
                        })()}
                        {/* .ovpn file picker - always show when VPN client is installed */}
                        {openvpnCheck.passed && (
                          <div className="mt-2 p-2 rounded bg-gray-50 dark:bg-gray-800/50 border border-gray-200 dark:border-gray-700">
                            <div className="flex items-center justify-between gap-2">
                              <div className="flex-1 min-w-0">
                                <div className="text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                                  VPN Configuration File
                                </div>
                                {config.openvpn_config_path ? (
                                  <div className="text-xs text-gray-600 dark:text-gray-400 truncate">
                                    {config.openvpn_config_path.split(/[\\/]/).pop()}
                                  </div>
                                ) : (
                                  <div className="text-xs text-amber-600 dark:text-amber-400">
                                    No .ovpn file selected
                                  </div>
                                )}
                              </div>
                              <button
                                onClick={browseVpn}
                                className="flex items-center gap-1.5 px-2 py-1 text-xs bg-gray-200 hover:bg-gray-300 dark:bg-gray-700 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-300 font-medium rounded transition-colors shrink-0"
                              >
                                <FolderOpen className="w-3 h-3" />
                                {config.openvpn_config_path ? 'Change File' : 'Browse'}
                              </button>
                            </div>
                          </div>
                        )}
                      </div>
                    </div>
                  )}

                  {/* VPN Connection Status */}
                  {vpnConnectionCheck && (
                    <div className="flex items-start gap-2">
                      {vpnConnectionCheck.passed ? (
                        <CheckCircle className="w-4 h-4 text-green-500 mt-0.5 shrink-0" />
                      ) : (
                        <AlertTriangle className="w-4 h-4 text-amber-500 mt-0.5 shrink-0" />
                      )}
                      <div className="flex-1 text-sm">
                        <span className="font-medium text-gray-900 dark:text-white">VPN Connection: </span>
                        <span className="text-gray-600 dark:text-gray-400">{vpnConnectionCheck.message}</span>
                      </div>
                      <div className="flex items-center gap-2 shrink-0">
                        {/* Connect button - shown when VPN is not connected */}
                        {vpnConnectionCheck.actionable && vpnConnectionCheck.action_id && !vpnConnectionCheck.passed && (
                          <>
                            <button
                              onClick={() => handleAction(vpnConnectionCheck.action_id!)}
                              disabled={runningAction !== null || !config.openvpn_config_path}
                              title={!config.openvpn_config_path ? 'Please select a .ovpn file first' : ''}
                              className="flex items-center gap-1.5 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed text-white font-medium rounded-lg transition-colors"
                            >
                              {runningAction === vpnConnectionCheck.action_id ? (
                                <Loader2 className="w-4 h-4 animate-spin" />
                              ) : (
                                <Play className="w-4 h-4" />
                              )}
                              Connect to VPN
                            </button>
                            {runningAction === vpnConnectionCheck.action_id && (
                              <button
                                onClick={() => setRunningAction(null)}
                                className="p-2 text-red-600 hover:text-red-700 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg transition-colors"
                                title="Stop VPN connection attempt"
                              >
                                <StopCircle className="w-5 h-5" />
                              </button>
                            )}
                          </>
                        )}
                        {/* Disconnect button - shown for CLI method when connected */}
                        {!isWindows && vpnConnectionCheck.passed && config.vpn_method === 'openvpn-cli' && (
                          <button
                            onClick={() => handleAction('disconnect_vpn')}
                            disabled={runningAction !== null}
                            className="flex items-center gap-1.5 px-3 py-1.5 text-sm bg-red-600 hover:bg-red-700 disabled:bg-gray-400 disabled:cursor-not-allowed text-white font-medium rounded-lg transition-colors"
                            title="Disconnect OpenVPN CLI daemon"
                          >
                            <StopCircle className="w-4 h-4" />
                            Disconnect VPN
                          </button>
                        )}
                      </div>
                    </div>
                  )}

                  {/* GitLab Connectivity Status */}
                  {vpnConnCheck && (
                    <div className="flex items-start gap-2">
                      {vpnConnCheck.passed ? (
                        <CheckCircle className="w-4 h-4 text-green-500 mt-0.5 shrink-0" />
                      ) : (
                        <AlertTriangle className="w-4 h-4 text-amber-500 mt-0.5 shrink-0" />
                      )}
                      <div className="flex-1 text-sm">
                        <span className="font-medium text-gray-900 dark:text-white">GitLab Connectivity: </span>
                        <span className="text-gray-600 dark:text-gray-400">{vpnConnCheck.message}</span>
                      </div>
                      {/* Connect button - shown when GitLab not reachable AND no VPN Connection check (Windows) */}
                      {!vpnConnectionCheck && vpnConnCheck.actionable && vpnConnCheck.action_id && !vpnConnCheck.passed && (
                        <div className="flex items-center gap-2 shrink-0">
                          <button
                            onClick={() => handleAction(vpnConnCheck.action_id!)}
                            disabled={runningAction !== null || !config.openvpn_config_path}
                            title={!config.openvpn_config_path ? 'Please select a .ovpn file first' : ''}
                            className="flex items-center gap-1.5 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed text-white font-medium rounded-lg transition-colors"
                          >
                            {runningAction === vpnConnCheck.action_id ? (
                              <Loader2 className="w-4 h-4 animate-spin" />
                            ) : (
                              <Play className="w-4 h-4" />
                            )}
                            Connect to VPN
                          </button>
                          {runningAction === vpnConnCheck.action_id && (
                            <button
                              onClick={() => setRunningAction(null)}
                              className="p-2 text-red-600 hover:text-red-700 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg transition-colors"
                              title="Stop VPN connection attempt"
                            >
                              <StopCircle className="w-5 h-5" />
                            </button>
                          )}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              </div>
            </div>
            {/* OpenVPN config file picker — show if no file selected AND VPN connectivity check exists but no VPN Connection check (Windows) */}
            {!vpnConnectionCheck && vpnConnCheck && !config.openvpn_config_path && (
              <div className="ml-8 mt-3 p-3 rounded-lg bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-300 dark:border-yellow-700">
                <div className="flex items-start gap-3">
                  <AlertTriangle className="w-5 h-5 text-yellow-600 dark:text-yellow-400 mt-0.5 shrink-0" />
                  <div className="flex-1">
                    <p className="text-sm text-yellow-800 dark:text-yellow-200 mb-2">
                      OpenVPN config file not set. Select your .ovpn file to enable VPN connection.
                    </p>
                    <button
                      onClick={browseVpn}
                      className="flex items-center gap-1.5 px-3 py-1.5 text-sm bg-yellow-600 hover:bg-yellow-700 text-white font-medium rounded-lg transition-colors"
                    >
                      <FolderOpen className="w-4 h-4" />
                      Browse for .ovpn file
                    </button>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}

        {/* Other checks */}
        {otherChecks.map((check) => (
          <div
            key={check.name}
            className={`flex items-start gap-3 p-4 rounded-lg border ${
              check.passed
                ? 'bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800'
                : check.warning
                ? 'bg-amber-50 dark:bg-amber-900/20 border-amber-200 dark:border-amber-700'
                : 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800'
            }`}
          >
            {check.passed ? (
              <CheckCircle className="w-5 h-5 text-green-500 mt-0.5 shrink-0" />
            ) : check.warning ? (
              <AlertTriangle className="w-5 h-5 text-amber-500 mt-0.5 shrink-0" />
            ) : (
              <XCircle className="w-5 h-5 text-red-500 mt-0.5 shrink-0" />
            )}
            <div className="flex-1 min-w-0">
              <div className="font-medium text-gray-900 dark:text-white">{check.name}</div>
              <div className="text-sm text-gray-600 dark:text-gray-400">{check.message}</div>
            </div>
            {/* Action button for actionable checks */}
            {check.actionable && check.action_id && !check.passed && (() => {
              const actionState = isActionDisabled(check.action_id!);
              const isDisabled = runningAction !== null || actionState.disabled;

              return (
                <div className="flex flex-col items-end gap-1 shrink-0">
                  <button
                    onClick={() => handleAction(check.action_id!)}
                    disabled={isDisabled}
                    className="flex items-center gap-1.5 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed text-white font-medium rounded-lg transition-colors"
                  >
                    {runningAction === check.action_id ? (
                      <Loader2 className="w-4 h-4 animate-spin" />
                    ) : (
                      <Play className="w-4 h-4" />
                    )}
                    {getActionButtonLabel(check.action_id)}
                  </button>
                  {actionState.disabled && actionState.reason && (
                    <span className="text-xs text-amber-600 dark:text-amber-400">
                      {actionState.reason}
                    </span>
                  )}
                </div>
              );
            })()}
          </div>
        ))}
      </div>

      {/* Comprehensive Precheck Logs — all prereq-related activity */}
      <div className="mt-4 border rounded-lg bg-gray-50 dark:bg-gray-900/20 border-gray-300 dark:border-gray-700">
        <button
          onClick={() => setLogsExpanded(!logsExpanded)}
          className="w-full flex items-center justify-between p-4 text-left hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors rounded-t-lg"
        >
          <div className="flex items-center gap-2">
            <ScrollText className="w-5 h-5 text-gray-600 dark:text-gray-400" />
            <span className="font-medium text-gray-900 dark:text-white">Precheck Activity Logs</span>
            <span className="text-xs text-gray-500 dark:text-gray-400">({prereqLogs.length} entries)</span>
          </div>
          <div className="flex items-center gap-2">
            {prereqLogs.length > 0 && (
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onClearPrereqLogs();
                }}
                className="p-1.5 text-gray-500 hover:text-red-600 dark:hover:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 rounded transition-colors"
                title="Clear logs"
              >
                <Trash2 className="w-4 h-4" />
              </button>
            )}
            {logsExpanded ? (
              <ChevronUp className="w-5 h-5 text-gray-500" />
            ) : (
              <ChevronDown className="w-5 h-5 text-gray-500" />
            )}
          </div>
        </button>
        <div
          className={`overflow-hidden transition-all duration-300 ease-in-out ${
            logsExpanded ? 'max-h-80' : 'max-h-0'
          }`}
        >
          {prereqLogs.length > 0 ? (
            <div className="border-t border-gray-700 bg-gray-950 max-h-80 overflow-y-auto font-mono text-xs px-4 py-3 space-y-0.5">
              {prereqLogs.map((entry, i) => {
                const colorClass = LOG_COLORS[entry.level] ?? 'text-gray-300';
                const ts = entry.ts ? new Date(entry.ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : '';
                return (
                  <div key={i} className={`leading-5 whitespace-pre-wrap break-all ${colorClass}`}>
                    <span className="text-gray-600 select-none">{ts && `${ts} `}</span>
                    <span className="text-blue-400 select-none">[Pre-flight Checks] </span>
                    {entry.line}
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="border-t border-gray-700 bg-gray-950 p-4 text-center">
              <p className="text-sm text-gray-500 italic">No precheck activity yet. Run checks or action buttons to see logs here.</p>
            </div>
          )}
        </div>
      </div>

      {/* Warning for failures */}
      {hasFailures && (
        <div className="mt-4 p-4 bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800 rounded-lg">
          <p className="text-sm text-yellow-800 dark:text-yellow-200">
            ⚠️ Some checks failed. You can still proceed but certain steps may fail.
            Fix the issues above and re-run checks for best results.
          </p>
        </div>
      )}

      {/* Footer */}
      <div className="flex items-center justify-between mt-6 pt-4 border-t border-gray-200 dark:border-gray-700">
        <button
          onClick={runChecks}
          disabled={checking}
          className="flex items-center gap-2 px-4 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 disabled:opacity-50 transition-colors"
        >
          <RefreshCw className={`w-4 h-4 ${checking ? 'animate-spin' : ''}`} />
          Re-run Checks
        </button>
        <button
          onClick={() => onNext('settings')}
          disabled={checking}
          className="flex items-center gap-2 px-6 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-300 text-white font-semibold rounded-lg transition-colors"
        >
          {allPassed ? 'Continue' : 'Continue Anyway'}
          <ChevronRight className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};
