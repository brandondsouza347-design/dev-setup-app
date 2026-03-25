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
  page: WizardPage;

  // Actions
  setPage: (p: WizardPage) => void;
  runPrereqCheck: () => Promise<void>;
  saveConfig: (cfg: UserConfig) => Promise<void>;
  startSetup: () => Promise<void>;
  retryStep: (id: string) => Promise<void>;
  skipStep: (id: string) => Promise<void>;
  resetSetup: () => Promise<void>;
  openTerminal: () => Promise<void>;
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
    postgres_db_name: 'dev_db',
    python_version: '3.9.21',
    node_version: '16.20.2',
    venv_name: 'erc',
    skip_already_installed: true,
  });
  const [prereqChecks, setPrereqChecks] = useState<PrereqCheck[]>([]);
  const [currentStepIndex, setCurrentStepIndex] = useState(0);
  const [setupStarted, setSetupStarted] = useState(false);
  const [setupComplete, setSetupComplete] = useState(false);
  const [isRunning, setIsRunning] = useState(false);

  const unlistenRefs = useRef<UnlistenFn[]>([]);

  // ── Bootstrap: detect OS, load steps and config ─────────────────────────
  useEffect(() => {
    (async () => {
      try {
        const info = await invoke<OsInfo>('detect_os');
        setOsInfo(info);

        const stepsData = await invoke<SetupStep[]>('get_setup_steps', { os: info.os });
        setSteps(stepsData);

        const cfg = await invoke<UserConfig>('get_config');
        setConfig(cfg);

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
        setStepResults((prev) => {
          const existing = prev[id] ?? {
            id,
            status: 'pending' as StepStatus,
            logs: [],
            error: null,
            retry_count: 0,
            duration_secs: null,
          };
          return {
            ...prev,
            [id]: { ...existing, status, error: error ?? null },
          };
        });
        if (status === 'running') {
          const idx = steps.findIndex((s) => s.id === id);
          if (idx >= 0) setCurrentStepIndex(idx);
        }
      });

      const unlistenComplete = await listen<boolean>('setup_complete', () => {
        if (!mounted) return;
        setSetupComplete(true);
        setIsRunning(false);
        setPage('complete');
      });

      unlistenRefs.current = [unlistenLog, unlistenStatus, unlistenComplete];
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
  }, []);

  const saveConfig = useCallback(async (cfg: UserConfig) => {
    await invoke('save_config', { input: cfg });
    setConfig(cfg);
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

  const retryStep = useCallback(async (id: string) => {
    setIsRunning(true);
    try {
      await invoke('retry_step', { stepId: id });
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
    page,
    setPage,
    runPrereqCheck,
    saveConfig,
    startSetup,
    retryStep,
    skipStep,
    resetSetup,
    openTerminal,
  };
}
