// hooks/useSetup.ts — Central state hook wiring Tauri commands to React state
import { useState, useEffect, useCallback, useRef } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen, UnlistenFn } from '@tauri-apps/api/event';
import type {
  OsInfo,
  SetupStep,
  StepResult,
  UserConfig,
  FullState,
  PrereqCheck,
  LogEvent,
  LogEntry,
  StepStatusEvent,
  StepStatus,
  WizardPage,
  AdminAgentStatus,
  RunHistory,
  CustomWorkflow,
} from '../types';

interface UseSetupReturn {
  // State
  osInfo: OsInfo | null;
  steps: SetupStep[];
  stepResults: Record<string, StepResult>;
  logs: Record<string, LogEntry[]>;
  config: UserConfig;
  prereqChecks: PrereqCheck[];
  currentStepIndex: number;
  setupStarted: boolean;
  setupComplete: boolean;
  isRunning: boolean;
  isRollingBackStep: boolean;
  page: WizardPage;
  // Revert
  revertSteps: SetupStep[];
  revertResults: Record<string, StepResult>;
  isReverting: boolean;
  revertComplete: boolean;
  // Workflow
  currentWorkflow: CustomWorkflow | null;
  workflowSteps: SetupStep[];
  workflowStepResults: Record<string, StepResult>;
  isRunningWorkflow: boolean;
  workflowComplete: boolean;
  currentWorkflowStepIndex: number;
  // Admin agent
  adminAgentStatus: AdminAgentStatus;
  adminAgentError: string | null;
  adminAgentLogs: string[];
  prereqLogs: LogEntry[];
  history: RunHistory[];

  // Actions
  setPage: (p: WizardPage) => void;
  runPrereqCheck: () => Promise<void>;
  handlePrereqAction: (actionId: string) => Promise<void>;
  saveConfig: (cfg: UserConfig) => Promise<void>;
  updateConfig: (key: keyof UserConfig, value: string | boolean | null) => void;
  startSetup: () => Promise<void>;
  stopSetup: () => Promise<void>;
  resumeSetup: () => Promise<void>;
  retryStep: (id: string) => Promise<void>;
  revertStep: (id: string) => Promise<void>;
  skipStep: (id: string) => Promise<void>;
  resetSetup: () => Promise<void>;
  openTerminal: () => Promise<void>;
  executeWorkflow: (workflow: CustomWorkflow) => Promise<void>;
  // Revert actions
  startRevert: () => Promise<void>;
  retryRevertStep: (id: string) => Promise<void>;
  resetRevert: () => void;
  // Admin agent actions
  requestAdminAgent: () => Promise<void>;
  shutdownAdminAgent: () => Promise<void>;
  // Log management
  clearLogs: () => void;
  clearPrereqLogs: () => void;
  // History management
  loadHistory: () => Promise<void>;
  clearHistoryByIds: (ids: string[]) => Promise<void>;
}

export function useSetup(): UseSetupReturn {
  const [page, setPage] = useState<WizardPage>('welcome');
  const [osInfo, setOsInfo] = useState<OsInfo | null>(null);
  const [steps, setSteps] = useState<SetupStep[]>([]);
  const [stepResults, setStepResults] = useState<Record<string, StepResult>>({});
  const [logs, setLogs] = useState<Record<string, LogEntry[]>>({});
  const [config, setConfig] = useState<UserConfig>({
    wsl_tar_path: null,
    wsl_install_dir: null,
    postgres_password: 'postgres',
    postgres_db_name: 'toogo_pos',
    python_version: '3.9.21',
    node_version: '22.10.0',
    venv_name: 'erc',
    skip_already_installed: false,
    skip_wsl_backup: false,
    openvpn_config_path: null,
    git_name: null,
    git_email: null,
    gitlab_pat: null,
    gitlab_repo_url: 'git@gitlab.toogoerp.net:root/erc.git',
    clone_dir: '/home/ubuntu/VsCodeProjects/erc',
    wsl_default_user: 'ubuntu',
    tenant_name: 'erckinetic',
    tenant_id: 't2070',
    cluster_name: 'stable',
    aws_access_key_id: null,
    aws_secret_access_key: null,
    wsl_backup_path: null,
  });
  const [prereqChecks, setPrereqChecks] = useState<PrereqCheck[]>([]);
  const [currentStepIndex, setCurrentStepIndex] = useState(0);
  const [setupStarted, setSetupStarted] = useState(false);
  const [setupComplete, setSetupComplete] = useState(false);
  const [isRunning, setIsRunning] = useState(false);
  const [isRollingBackStep, setIsRollingBackStep] = useState(false);

  // Admin agent state
  const [adminAgentStatus, setAdminAgentStatus] = useState<AdminAgentStatus>('idle');
  const [adminAgentError, setAdminAgentError] = useState<string | null>(null);
  const [adminAgentLogs, setAdminAgentLogs] = useState<string[]>([]);
  const [prereqLogs, setPrereqLogs] = useState<LogEntry[]>([]);
  const [history, setHistory] = useState<RunHistory[]>([]);
  const [revertSteps, setRevertSteps] = useState<SetupStep[]>([]);
  const [revertResults, setRevertResults] = useState<Record<string, StepResult>>({});
  const [isReverting, setIsReverting] = useState(false);
  const [revertComplete, setRevertComplete] = useState(false);
  const revertStepIdsRef = useRef<Set<string>>(new Set());

  // Workflow execution state
  const [currentWorkflow, setCurrentWorkflow] = useState<CustomWorkflow | null>(null);
  const [workflowSteps, setWorkflowSteps] = useState<SetupStep[]>([]);
  const [workflowStepResults, setWorkflowStepResults] = useState<Record<string, StepResult>>({});
  const [isRunningWorkflow, setIsRunningWorkflow] = useState(false);
  const [workflowComplete, setWorkflowComplete] = useState(false);
  const [currentWorkflowStepIndex, setCurrentWorkflowStepIndex] = useState(0);

  const unlistenRefs = useRef<UnlistenFn[]>([]);

  // ── Bootstrap: detect OS, load steps and config ─────────────────────────
  useEffect(() => {
    (async () => {
      try {
        const info = await invoke<OsInfo>('detect_os');
        setOsInfo(info);

        const stepsData = await invoke<SetupStep[]>('get_setup_steps', { os: info.os });
        setSteps(stepsData);

        // Load revert steps (Windows only — empty on macOS)
        const revertData = await invoke<SetupStep[]>('get_revert_steps', { os: info.os });
        setRevertSteps(revertData);
        revertStepIdsRef.current = new Set(revertData.map((s) => s.id));

        const cfg = await invoke<UserConfig>('get_config');
        setConfig(cfg);

        // Load run history
        const hist = await invoke<RunHistory[]>('load_run_history');
        setHistory(hist);

        // Restore previous state if any
        const state = await invoke<FullState>('get_state');
        if (state.setup_started) {
          const resultsMap: Record<string, StepResult> = {};
          state.steps.forEach((r) => (resultsMap[r.id] = r));
          setStepResults(resultsMap);
          setCurrentStepIndex(state.current_step_index);
          setSetupStarted(state.setup_started);
          setSetupComplete(state.setup_complete);
          if (state.setup_started && !state.setup_complete) {
            setPage('progress');
          } else if (state.setup_complete) {
            setPage('complete');
          }
        }
      } catch (e) {
        console.error('Bootstrap error:', e);
      }
    })();

    return () => {
      unlistenRefs.current.forEach((fn) => fn());
    };
  }, []);

  // ── Subscribe to Tauri events ─────────────────────────────────────────────
  useEffect(() => {
    let mounted = true;

    const setupListeners = async () => {
      const unlistenLog = await listen<LogEvent>('step_log', (event) => {
        if (!mounted) return;
        const { step_id, line, level } = event.payload;

        // Capture all prereq-related logs for comprehensive logging
        const prereqStepIds = ['__prereq__', '__prereq_action__', 'install_openvpn', 'connect_vpn', 'install_openvpn_mac', 'connect_vpn_mac', 'xcode_clt', 'homebrew'];
        if (prereqStepIds.includes(step_id)) {
          setPrereqLogs((prev) => [...prev, { stepId: step_id, line, level, ts: Date.now() }]);
        }

        setLogs((prev) => {
          const existing = prev[step_id] ?? [];
          return {
            ...prev,
            [step_id]: [...existing, { stepId: step_id, line, level, ts: Date.now() }],
          };
        });
      });

      const unlistenStatus = await listen<StepStatusEvent>('step_status', (event) => {
        if (!mounted) return;
        const { id, status, error } = event.payload;
        const isRevert = revertStepIdsRef.current.has(id);

        const result = {
          id,
          status,
          error: error ?? null,
          logs: [] as string[],
          retry_count: 0,
          duration_secs: null,
        };

        if (isRevert) {
          setRevertResults((prev) => ({
            ...prev,
            [id]: { ...(prev[id] ?? result), status, error: error ?? null },
          }));
        } else {
          setStepResults((prev) => {
            const existing = prev[id] ?? {
              id,
              status: 'pending' as StepStatus,
              logs: [],
              error: null,
              retry_count: 0,
              duration_secs: null,
            };
            return { ...prev, [id]: { ...existing, status, error: error ?? null } };
          });
          if (status === 'running') {
            // Ensure isRunning is true when any step starts running
            // This handles cases where state might have been reset between startSetup() and step execution
            setIsRunning(true);
            const idx = steps.findIndex((s) => s.id === id);
            if (idx >= 0) setCurrentStepIndex(idx);
          }
        }
        // Emit a synthetic log entry for status transitions so Live Logs shows them
        const statusEntry: LogEntry = (() => {
          switch (status) {
            case 'done':
              return { stepId: id, line: '✓ Step completed successfully', level: 'success', ts: Date.now() };
            case 'failed':
              return { stepId: id, line: `✗ Step failed${error ? `: ${error}` : ''}`, level: 'error', ts: Date.now() };
            case 'skipped':
              return { stepId: id, line: '⏭ Step skipped', level: 'warn', ts: Date.now() };
            case 'running':
              return { stepId: id, line: '▶ Step started', level: 'info', ts: Date.now() };
            default:
              return { stepId: id, line: `Status: ${status}`, level: 'info', ts: Date.now() };
          }
        })();
        setLogs((prev) => ({
          ...prev,
          [id]: [...(prev[id] ?? []), statusEntry],
        }));
      });

      const unlistenComplete = await listen<boolean>('setup_complete', async () => {
        if (!mounted) return;
        setSetupComplete(true);
        setIsRunning(false);
        setPage('complete');
        // Reload history to show the completed run
        try {
          const hist = await invoke<RunHistory[]>('load_run_history');
          setHistory(hist);
        } catch (err) {
          console.error('Failed to reload history after setup complete:', err);
        }
      });

      const unlistenRevertComplete = await listen<boolean>('revert_complete', async () => {
        if (!mounted) return;
        setRevertComplete(true);
        setIsReverting(false);
        // Reload history to show the completed revert
        try {
          const hist = await invoke<RunHistory[]>('load_run_history');
          setHistory(hist);
        } catch (err) {
          console.error('Failed to reload history after revert complete:', err);
        }
      });

      const unlistenAgentLog = await listen<{ line: string; level: string }>('admin_agent_log', (event) => {
        if (!mounted) return;
        setAdminAgentLogs((prev) => [...prev, event.payload.line]);
      });

      unlistenRefs.current = [unlistenLog, unlistenStatus, unlistenComplete, unlistenRevertComplete, unlistenAgentLog];
    };

    setupListeners();
    return () => {
      mounted = false;
    };
  }, [steps]);

  // ── Actions ───────────────────────────────────────────────────────────────

  const runPrereqCheck = useCallback(async () => {
    const checks = await invoke<PrereqCheck[]>('check_prerequisites');
    setPrereqChecks(checks);
    // Also push results into logs so Live Logs panel shows them
    const now = Date.now();
    const entries: LogEntry[] = checks.map((c, i) => ({
      stepId: '__prereq__',
      line: `${c.passed ? '✓' : '✗'} ${c.name}: ${c.message}`,
      level: c.passed ? 'success' : 'error',
      ts: now + i,
    }));
    setLogs((prev) => ({
      ...prev,
      __prereq__: [...(prev['__prereq__'] ?? []), ...entries],
    }));
    // Also add to prereqLogs for the Precheck Activity Logs section
    setPrereqLogs((prev) => [...prev, ...entries]);
  }, []);

  const handlePrereqAction = useCallback(async (actionId: string) => {
    // Map action IDs to Tauri commands
    let command: string;
    switch (actionId) {
      case 'install_openvpn':
        command = 'install_openvpn_prereq';
        break;
      case 'install_xcode_clt':
        command = 'install_xcode_clt_prereq';
        break;
      case 'install_homebrew':
        command = 'install_homebrew_prereq';
        break;
      case 'connect_vpn':
        command = 'connect_vpn_prereq';
        break;
      default:
        throw new Error(`Unknown prereq action: ${actionId}`);
    }

    try {
      await invoke(command);
    } catch (e) {
      const msg = typeof e === 'string' ? e : (e as any)?.message ?? String(e);
      setLogs((prev) => ({
        ...prev,
        __prereq__: [...(prev['__prereq__'] ?? []), { stepId: '__prereq__', line: `✗ Action failed: ${msg}`, level: 'error', ts: Date.now() }],
      }));
      throw e; // Re-throw so PrereqScreen can handle it
    }
  }, []);

  const saveConfig = useCallback(async (cfg: UserConfig) => {
    await invoke('save_config', { input: cfg });
    setConfig(cfg);
  }, []);

  const updateConfig = useCallback((key: keyof UserConfig, value: string | boolean | null) => {
    setConfig((prev) => ({ ...prev, [key]: value }));
  }, []);

  const startSetup = useCallback(async () => {
    setIsRunning(true);
    setSetupStarted(true);
    setPage('progress');
    try {
      await invoke('start_setup');
    } catch (e) {
      console.error('Setup error:', e);
      setIsRunning(false);
    }
  }, []);

  const executeWorkflow = useCallback(async (workflow: CustomWorkflow) => {
    // Filter steps to only include those in the workflow
    const filteredSteps = steps.filter((step) => workflow.step_ids.includes(step.id));
    // Order them according to workflow step order
    const orderedSteps = workflow.step_ids
      .map((id) => filteredSteps.find((s) => s.id === id))
      .filter((s): s is SetupStep => s !== undefined);

    setCurrentWorkflow(workflow);
    setWorkflowSteps(orderedSteps);
    setWorkflowStepResults({});
    setWorkflowComplete(false);
    setCurrentWorkflowStepIndex(0);
    setIsRunningWorkflow(true);
    setPage('custom-progress');

    try {
      // Merge workflow settings with global config (workflow settings take priority)
      // Note: mergeWorkflowSettings will be imported when start_workflow is implemented
      // const mergedConfig = mergeWorkflowSettings(config, workflow.settings);

      // TODO: Backend command start_workflow needs to be implemented
      // It should accept: workflowId, mergedConfig
      // The merged config should be used instead of global config during workflow execution
      await invoke('start_workflow', {
        workflowId: workflow.id,
        // When implemented, pass: config: mergedConfig
      });
    } catch (e) {
      console.error('Workflow execution error:', e);
      setIsRunningWorkflow(false);
    }
  }, [steps]);

  const retryStep = useCallback(async (id: string) => {
    setIsRunning(true);
    try {
      await invoke('retry_step', { stepId: id });
    } finally {
      setIsRunning(false);
    }
  }, []);

  const revertStep = useCallback(async (id: string) => {
    setIsRollingBackStep(true);
    try {
      await invoke('revert_setup_step', { stepId: id });
    } catch (e) {
      const msg = typeof e === 'string' ? e : (e as any)?.message ?? String(e);
      setLogs((prev) => ({
        ...prev,
        [id]: [...(prev[id] ?? []), { stepId: id, line: `✗ Revert failed: ${msg}`, level: 'error', ts: Date.now() }],
      }));
    } finally {
      setIsRollingBackStep(false);
    }
  }, []);

  const resumeSetup = useCallback(async () => {
    setIsRunning(true);
    try {
      await invoke('resume_setup');
    } catch (e) {
      console.error('Resume error:', e);
    } finally {
      setIsRunning(false);
    }
  }, []);

  const skipStep = useCallback(async (id: string) => {
    await invoke('skip_step', { stepId: id });
    setStepResults((prev) => ({
      ...prev,
      [id]: { ...(prev[id] ?? { id, logs: [], error: null, retry_count: 0, duration_secs: null }), status: 'skipped' },
    }));
    setLogs((prev) => ({
      ...prev,
      [id]: [...(prev[id] ?? []), { stepId: id, line: '⏭ Step skipped by user', level: 'warn', ts: Date.now() }],
    }));
  }, []);

  const resetSetup = useCallback(async () => {
    await invoke('reset_state');
    setStepResults({});
    setLogs({});
    setCurrentStepIndex(0);
    setSetupStarted(false);
    setSetupComplete(false);
    setIsRunning(false);
    setPage('welcome');
  }, []);

  const openTerminal = useCallback(async () => {
    await invoke('open_terminal');
  }, []);

  const startRevert = useCallback(async () => {
    // Save current config first to ensure skip_wsl_backup and other settings are persisted
    try {
      await invoke('save_config', { input: config });
    } catch (e) {
      console.error('Failed to save config before revert:', e);
    }

    setIsReverting(true);
    setRevertComplete(false);
    setRevertResults({});
    try {
      await invoke('start_revert');
    } catch (e) {
      console.error('Revert error:', e);
      setIsReverting(false);
    }
  }, [config]);

  const retryRevertStep = useCallback(async (id: string) => {
    setIsReverting(true);
    try {
      await invoke('run_step', { stepId: id });
    } finally {
      setIsReverting(false);
    }
  }, []);

  const resetRevert = useCallback(() => {
    setRevertResults({});
    setRevertComplete(false);
    setIsReverting(false);
  }, []);

  const requestAdminAgent = useCallback(async () => {
    setAdminAgentStatus('requesting');
    setAdminAgentError(null);
    setAdminAgentLogs([]);
    try {
      await invoke('request_admin_agent');
      setAdminAgentStatus('ready');
    } catch (e) {
      const msg = typeof e === 'string' ? e : (e as any)?.message ?? String(e);
      setAdminAgentStatus('error');
      setAdminAgentError(msg);
    }
  }, []);

  const shutdownAdminAgent = useCallback(async () => {
    await invoke('shutdown_admin_agent');
    setAdminAgentStatus('idle');
    setAdminAgentError(null);
  }, []);

  const stopSetup = useCallback(async () => {
    try {
      await invoke('stop_setup');
    } catch (e) {
      console.error('Stop error:', e);
    }
    setIsRunning(false);
  }, []);

  // ── Clear logs ─────────────────────────────────────────────────────────
  const clearLogs = useCallback(() => {
    setLogs({});
  }, []);

  const clearPrereqLogs = useCallback(() => {
    setPrereqLogs([]);
  }, []);

  const loadHistory = useCallback(async () => {
    try {
      const hist = await invoke<RunHistory[]>('load_run_history');
      setHistory(hist);
    } catch (err) {
      console.error('Failed to load history:', err);
    }
  }, []);

  const clearHistoryByIds = useCallback(async (ids: string[]) => {
    try {
      await invoke('clear_run_history_by_ids', { ids });
    } catch (err) {
      console.error('Failed to clear history:', err);
    }
  }, []);

  return {
    osInfo,
    steps,
    stepResults,
    logs,
    config,
    prereqChecks,
    currentStepIndex,
    setupStarted,
    setupComplete,
    isRunning,
    isRollingBackStep,
    page,
    revertSteps,
    revertResults,
    isReverting,
    revertComplete,
    currentWorkflow,
    workflowSteps,
    workflowStepResults,
    isRunningWorkflow,
    workflowComplete,
    currentWorkflowStepIndex,
    setPage,
    runPrereqCheck,
    handlePrereqAction,
    saveConfig,
    updateConfig,
    startSetup,
    executeWorkflow,
    stopSetup,
    resumeSetup,
    retryStep,
    revertStep,
    skipStep,
    resetSetup,
    openTerminal,
    startRevert,
    retryRevertStep,
    resetRevert,
    adminAgentStatus,
    adminAgentError,
    adminAgentLogs,
    prereqLogs,
    history,
    requestAdminAgent,
    shutdownAdminAgent,
    clearLogs,
    clearPrereqLogs,
    loadHistory,
    clearHistoryByIds,
  };
}
