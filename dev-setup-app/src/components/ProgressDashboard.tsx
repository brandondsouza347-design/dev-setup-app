// components/ProgressDashboard.tsx — Main live-progress view during installation
import React, { useState, useRef, useEffect } from 'react';
import {
  CheckCircle2, XCircle, Loader2, SkipForward, RotateCcw,
  ChevronDown, ChevronRight, Terminal, Clock, ScrollText, Undo2, StopCircle, Trash2, Power
} from 'lucide-react';
import type { SetupStep, StepResult, LogEntry, WizardPage } from '../types';
import { StepBadge } from './StepBadge';
import { invoke } from '@tauri-apps/api/core';

interface Props {
  steps: SetupStep[];
  revertSteps: SetupStep[];
  stepResults: Record<string, StepResult>;
  logs: Record<string, LogEntry[]>;
  currentStepIndex: number;
  isRunning: boolean;
  isRollingBackStep: boolean;
  setupComplete: boolean;
  onRetry: (id: string) => Promise<void>;
  onRevertStep: (id: string) => Promise<void>;
  onSkip: (id: string) => Promise<void>;
  onContinue: () => Promise<void>;
  onOpenTerminal: () => void;
  onStop: () => Promise<void>;
  onGoTo: (page: WizardPage) => void;
  onClearLogs: () => void;
}

// Extend LogEntry with ts field for use internally
type InternalLogEntry = LogEntry;

export const ProgressDashboard: React.FC<Props> = ({
  steps,
  revertSteps,
  stepResults,
  logs,
  currentStepIndex,
  isRunning,
  isRollingBackStep,
  setupComplete,
  onRetry,
  onRevertStep,
  onSkip,
  onContinue,
  onOpenTerminal,
  onStop,
  onGoTo,
  onClearLogs,
}) => {
  const [expandedStep, setExpandedStep] = useState<string | null>(null);
  const [retrying, setRetrying] = useState<string | null>(null);
  const [reverting, setReverting] = useState<string | null>(null);
  const [logsOpen, setLogsOpen] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const logsEndRef = useRef<HTMLDivElement>(null);

  // Auto-expand the currently running step
  useEffect(() => {
    if (steps[currentStepIndex]) {
      setExpandedStep(steps[currentStepIndex].id);
    }
  }, [currentStepIndex, steps]);

  // Auto-scroll step log to bottom
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [logs]);

  // Auto-scroll aggregated log panel to bottom when open
  useEffect(() => {
    if (logsOpen) {
      logsEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [logs, logsOpen]);

  // Flatten + sort all log entries across all steps (plus pre-flight checks) by timestamp
  const allLogs: (InternalLogEntry & { stepTitle: string })[] = [
    ...(logs['__prereq__'] ?? []).map((entry) => ({ ...entry, stepTitle: 'Pre-flight Checks' })),
    ...steps.flatMap((step) =>
      (logs[step.id] ?? []).map((entry) => ({ ...entry, stepTitle: step.title }))
    ),
    ...revertSteps.flatMap((step) =>
      (logs[step.id] ?? []).map((entry) => ({ ...entry, stepTitle: step.title }))
    ),
  ].sort((a, b) => (a.ts ?? 0) - (b.ts ?? 0));

  const handleRetry = async (id: string) => {
    setRetrying(id);
    try {
      await onRetry(id);
    } finally {
      setRetrying(null);
    }
  };

  const handleRevert = async (id: string) => {
    setReverting(id);
    try {
      await onRevertStep(id);
    } finally {
      setReverting(null);
    }
  };

  const handleRestartSystem = async () => {
    const confirmed = window.confirm(
      'Your system will restart in 10 seconds.\n\n' +
      'Please save all your work before proceeding.\n\n' +
      'After restart, re-launch this application to continue setup.'
    );

    if (confirmed) {
      try {
        await invoke('restart_system');
      } catch (err) {
        console.error('Failed to restart system:', err);
        alert('Failed to restart system. Please restart manually.');
      }
    }
  };

  // Helper to detect if a step was already installed
  const wasAlreadyInstalled = (stepId: string): boolean => {
    const stepLogs = logs[stepId] ?? [];
    return stepLogs.some(log =>
      log.line.includes('already installed') ||
      log.line.includes('Already installed') ||
      log.line.includes('already exists')
    );
  };

  const doneCount = Object.values(stepResults).filter((r) => r.status === 'done').length;
  const failedCount = Object.values(stepResults).filter((r) => r.status === 'failed').length;
  const progress = steps.length > 0 ? (doneCount / steps.length) * 100 : 0;
  const isBusy = isRunning || isRollingBackStep;
  // Show "Continue Setup" when: not running, not complete, at least one step done,
  // and no currently failed steps — i.e. a retry just succeeded mid-sequence.
  const showContinue = !isBusy && !setupComplete && doneCount > 0 && failedCount === 0;

  return (
    <div className="flex flex-col h-full">
      {/* Top summary bar */}
      <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800">
        <div className="flex items-center justify-between mb-2">
          <h2 className="font-bold text-gray-900 dark:text-white">
            {setupComplete
              ? '✅ Setup Complete!'
              : isRunning
              ? '⚙️ Installing…'
              : failedCount > 0
              ? '⚠️ Action Required'
              : 'Setup Progress'}
          </h2>
          <div className="flex items-center gap-4 text-sm text-gray-500">
            <span className="flex items-center gap-1 text-green-600 dark:text-green-400">
              <CheckCircle2 className="w-4 h-4" /> {doneCount} done
            </span>
            {failedCount > 0 && (
              <span className="flex items-center gap-1 text-red-500">
                <XCircle className="w-4 h-4" /> {failedCount} failed
              </span>
            )}
            <span>{steps.length - doneCount - failedCount} remaining</span>
            {isRunning && (
              <button
                onClick={onStop}
                className="flex items-center gap-1 px-3 py-1 text-xs bg-red-600 hover:bg-red-700 text-white rounded-lg transition-colors"
                title="Stop the current step"
              >
                <StopCircle className="w-3.5 h-3.5" />
                Stop
              </button>
            )}
          </div>
        </div>
        {/* Progress bar */}
        <div className="h-2 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden">
          <div
            className="h-full bg-blue-500 rounded-full transition-all duration-500"
            style={{ width: `${progress}%` }}
          />
        </div>
      </div>

      {/* Steps list */}
      <div className="flex-1 overflow-y-auto px-4 py-3 space-y-2">
        {steps.map((step, idx) => {
          const result = stepResults[step.id];
          const status = result?.status ?? 'pending';
          const isExpanded = expandedStep === step.id;
          const stepLogs = (logs[step.id] ?? []) as InternalLogEntry[];
          const isCurrent = idx === currentStepIndex && isRunning;
          const hasLaterCompletedSteps = steps
            .slice(idx + 1)
            .some((laterStep) => (stepResults[laterStep.id]?.status ?? 'pending') === 'done');
          const canRevert =
            !isBusy &&
            failedCount > 0 &&
            step.rollback_steps.length > 0 &&
            !hasLaterCompletedSteps &&
            (status === 'done' || status === 'failed');

          return (
            <div
              key={step.id}
              className={`rounded-xl border transition-all duration-200 ${
                status === 'running'
                  ? 'border-blue-400 dark:border-blue-600 shadow-md'
                  : status === 'failed'
                  ? 'border-red-300 dark:border-red-700'
                  : status === 'done'
                  ? 'border-green-200 dark:border-green-800'
                  : 'border-gray-200 dark:border-gray-700'
              } bg-white dark:bg-gray-800`}
            >
              {/* Step header */}
              <div
                className="flex items-center gap-3 p-4 cursor-pointer select-none"
                onClick={() => setExpandedStep(isExpanded ? null : step.id)}
              >
                {/* Status icon */}
                <div className="shrink-0">
                  {status === 'running' ? (
                    <Loader2 className="w-5 h-5 text-blue-500 animate-spin" />
                  ) : status === 'done' ? (
                    <CheckCircle2 className="w-5 h-5 text-green-500" />
                  ) : status === 'failed' ? (
                    <XCircle className="w-5 h-5 text-red-500" />
                  ) : status === 'skipped' ? (
                    <SkipForward className="w-5 h-5 text-yellow-400" />
                  ) : (
                    <div className="w-5 h-5 rounded-full border-2 border-gray-300 dark:border-gray-600" />
                  )}
                </div>

                {/* Title + badge */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className={`text-sm font-medium ${isCurrent ? 'text-blue-700 dark:text-blue-300' : 'text-gray-900 dark:text-white'}`}>
                      {idx + 1}. {step.title}
                    </span>
                    <StepBadge status={status} wasAlreadyInstalled={wasAlreadyInstalled(step.id)} />
                    {result?.duration_secs != null && (
                      <span className="flex items-center gap-0.5 text-xs text-gray-400">
                        <Clock className="w-3 h-3" />
                        {result.duration_secs}s
                      </span>
                    )}
                    {result?.retry_count != null && result.retry_count > 0 && (
                      <span className="text-xs text-gray-400">
                        (retried {result.retry_count}×)
                      </span>
                    )}
                  </div>
                  {result?.error && (
                    <p className="text-xs text-red-500 mt-0.5 truncate">{result.error}</p>
                  )}
                </div>

                {/* Action buttons */}
                {status === 'failed' && !isBusy && (
                  <div className="flex items-center gap-2 shrink-0" onClick={(e) => e.stopPropagation()}>
                    <button
                      onClick={() => handleRetry(step.id)}
                      disabled={retrying === step.id || reverting === step.id}
                      className="flex items-center gap-1 px-3 py-1 text-xs bg-blue-600 hover:bg-blue-700 text-white rounded-lg disabled:opacity-50 transition-colors"
                    >
                      <RotateCcw className={`w-3 h-3 ${retrying === step.id ? 'animate-spin' : ''}`} />
                      Retry
                    </button>
                    {step.rollback_steps.length > 0 && !hasLaterCompletedSteps && (
                      <button
                        onClick={() => handleRevert(step.id)}
                        disabled={reverting === step.id}
                        className="flex items-center gap-1 px-3 py-1 text-xs border border-red-300 dark:border-red-700 text-red-600 dark:text-red-400 rounded-lg hover:bg-red-50 dark:hover:bg-red-950/40 disabled:opacity-50 transition-colors"
                      >
                        <Undo2 className={`w-3 h-3 ${reverting === step.id ? 'animate-spin' : ''}`} />
                        Revert Step
                      </button>
                    )}
                    {!step.required && (
                      <button
                        onClick={() => onSkip(step.id)}
                        className="flex items-center gap-1 px-3 py-1 text-xs border border-gray-300 dark:border-gray-600 text-gray-600 dark:text-gray-400 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
                      >
                        <SkipForward className="w-3 h-3" />
                        Skip
                      </button>
                    )}
                  </div>
                )}

                {status === 'done' && canRevert && (
                  <div className="flex items-center gap-2 shrink-0" onClick={(e) => e.stopPropagation()}>
                    <button
                      onClick={() => handleRevert(step.id)}
                      disabled={reverting === step.id}
                      className="flex items-center gap-1 px-3 py-1 text-xs border border-red-300 dark:border-red-700 text-red-600 dark:text-red-400 rounded-lg hover:bg-red-50 dark:hover:bg-red-950/40 disabled:opacity-50 transition-colors"
                    >
                      <Undo2 className={`w-3 h-3 ${reverting === step.id ? 'animate-spin' : ''}`} />
                      Revert Step
                    </button>
                  </div>
                )}

                {/* Expand toggle */}
                <div className="shrink-0 text-gray-400">
                  {isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                </div>
              </div>

              {/* Log panel with smooth transition */}
              <div
                className={`border-t border-gray-100 dark:border-gray-700 transition-all duration-300 ease-in-out overflow-hidden ${
                  isExpanded ? 'max-h-80' : 'max-h-0 border-t-0'
                }`}
              >
                <div className="p-3 bg-gray-950 rounded-b-xl max-h-80 overflow-y-auto font-mono text-xs">
                  {stepLogs.length === 0 ? (
                    <p className="text-gray-500 italic">No output yet.</p>
                  ) : (
                    stepLogs.map((entry, i) => (
                      <LogLine key={i} entry={entry} />
                    ))
                  )}
                  <div ref={bottomRef} />
                </div>
              </div>

              {/* Restart System Button - shown when WSL requires restart */}
              {result?.restart_required && status === 'done' && (
                <div className="p-4 border-t border-orange-200 dark:border-orange-900 bg-gradient-to-r from-orange-50 to-red-50 dark:from-orange-950/30 dark:to-red-950/30">
                  <div className="flex items-start gap-3">
                    <Power className="w-5 h-5 text-orange-600 dark:text-orange-400 shrink-0 mt-0.5" />
                    <div className="flex-1">
                      <h4 className="text-sm font-semibold text-orange-900 dark:text-orange-200 mb-1">
                        System Restart Required
                      </h4>
                      <p className="text-xs text-orange-700 dark:text-orange-300 mb-3">
                        WSL features have been enabled for the first time. Windows must restart before WSL can be used.
                        After restarting, re-launch this application to continue setup.
                      </p>
                      <button
                        onClick={handleRestartSystem}
                        className="flex items-center gap-2 px-4 py-2 bg-gradient-to-r from-orange-600 to-red-600 hover:from-orange-700 hover:to-red-700 text-white text-sm font-medium rounded-lg shadow-md hover:shadow-lg transition-all duration-200"
                      >
                        <Power className="w-4 h-4" />
                        Restart System Now
                        <span className="text-xs opacity-90">(10s countdown)</span>
                      </button>
                    </div>
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Aggregated Live Logs panel */}
      <div className="border-t border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800">
        {/* Panel header / toggle */}
        <button
          className="w-full flex items-center justify-between px-6 py-2 text-sm font-medium text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-750 transition-colors select-none"
          onClick={() => setLogsOpen((o) => !o)}
        >
          <span className="flex items-center gap-2">
            <ScrollText className="w-4 h-4 text-gray-400" />
            Live Logs
            {allLogs.length > 0 && (
              <span className="px-1.5 py-0.5 text-xs rounded-full bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400">
                {allLogs.length}
              </span>
            )}
          </span>
          <div className="flex items-center gap-2">
            {allLogs.length > 0 && (
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onClearLogs();
                }}
                className="p-1.5 text-gray-500 hover:text-red-600 dark:hover:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 rounded transition-colors"
                title="Clear logs"
              >
                <Trash2 className="w-4 h-4" />
              </button>
            )}
            {logsOpen
              ? <ChevronDown className="w-4 h-4 text-gray-400" />
              : <ChevronRight className="w-4 h-4 text-gray-400" />}
          </div>
        </button>

        {logsOpen && (
          <div className="border-t border-gray-100 dark:border-gray-700 bg-gray-950 max-h-56 overflow-y-auto font-mono text-xs px-4 py-3 space-y-0.5">
            {allLogs.length === 0 ? (
              <p className="text-gray-500 italic">No log output yet.</p>
            ) : (
              allLogs.map((entry, i) => (
                <AggregatedLogLine key={i} entry={entry} />
              ))
            )}
            <div ref={logsEndRef} />
          </div>
        )}
      </div>

      {/* Footer action bar */}
      <div className="px-6 py-3 border-t border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <button
            onClick={onOpenTerminal}
            className="flex items-center gap-2 text-sm text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 transition-colors"
          >
            <Terminal className="w-4 h-4" />
            Open Terminal
          </button>
          {!isBusy && doneCount > 0 && (
            <button
              onClick={() => onGoTo('revert')}
              className="flex items-center gap-2 text-sm text-red-500 hover:text-red-700 dark:hover:text-red-400 transition-colors"
            >
              <Undo2 className="w-4 h-4" />
              Revert Setup
            </button>
          )}
        </div>
        {setupComplete && (
          <button
            onClick={() => onGoTo('complete')}
            className="px-6 py-2 bg-green-600 hover:bg-green-700 text-white font-semibold rounded-lg transition-colors"
          >
            View Summary →
          </button>
        )}
        {showContinue && (
          <button
            onClick={onContinue}
            className="px-6 py-2 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg transition-colors"
          >
            Continue Setup →
          </button>
        )}
      </div>
    </div>
  );
};

// ─── Log line renderer ───────────────────────────────────────────────────────

const LOG_COLORS: Record<string, string> = {
  info:    'text-gray-300',
  warn:    'text-yellow-400',
  error:   'text-red-400',
  success: 'text-green-400',
};

const LogLine: React.FC<{ entry: InternalLogEntry }> = ({ entry }) => {
  const colorClass = LOG_COLORS[entry.level] ?? 'text-gray-300';
  return (
    <div className={`leading-5 whitespace-pre-wrap break-all ${colorClass}`}>
      {entry.line}
    </div>
  );
};

const AggregatedLogLine: React.FC<{ entry: InternalLogEntry & { stepTitle: string } }> = ({ entry }) => {
  const colorClass = LOG_COLORS[entry.level] ?? 'text-gray-300';
  const ts = entry.ts ? new Date(entry.ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : '';
  return (
    <div className={`leading-5 whitespace-pre-wrap break-all ${colorClass}`}>
      <span className="text-gray-600 select-none">{ts && `${ts} `}</span>
      <span className="text-blue-400 select-none">[{entry.stepTitle}] </span>
      {entry.line}
    </div>
  );
};
