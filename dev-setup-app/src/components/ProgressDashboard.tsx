// components/ProgressDashboard.tsx — Main live-progress view during installation
import React, { useState, useRef, useEffect } from 'react';
import {
  CheckCircle2, XCircle, Loader2, SkipForward, RotateCcw,
  ChevronDown, ChevronRight, Terminal, Clock
} from 'lucide-react';
import type { SetupStep, StepResult, LogEntry, WizardPage } from '../types';
import { StepBadge } from './StepBadge';

interface Props {
  steps: SetupStep[];
  stepResults: Record<string, StepResult>;
  logs: Record<string, LogEntry[]>;
  currentStepIndex: number;
  isRunning: boolean;
  setupComplete: boolean;
  onRetry: (id: string) => Promise<void>;
  onSkip: (id: string) => Promise<void>;
  onOpenTerminal: () => void;
  onGoTo: (page: WizardPage) => void;
}

// Extend LogEntry with ts field for use internally
type InternalLogEntry = LogEntry;

export const ProgressDashboard: React.FC<Props> = ({
  steps,
  stepResults,
  logs,
  currentStepIndex,
  isRunning,
  setupComplete,
  onRetry,
  onSkip,
  onOpenTerminal,
  onGoTo,
}) => {
  const [expandedStep, setExpandedStep] = useState<string | null>(null);
  const [retrying, setRetrying] = useState<string | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  // Auto-expand the currently running step
  useEffect(() => {
    if (steps[currentStepIndex]) {
      setExpandedStep(steps[currentStepIndex].id);
    }
  }, [currentStepIndex, steps]);

  // Auto-scroll log to bottom
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [logs]);

  const handleRetry = async (id: string) => {
    setRetrying(id);
    try {
      await onRetry(id);
    } finally {
      setRetrying(null);
    }
  };

  const doneCount = Object.values(stepResults).filter((r) => r.status === 'done').length;
  const failedCount = Object.values(stepResults).filter((r) => r.status === 'failed').length;
  const progress = steps.length > 0 ? (doneCount / steps.length) * 100 : 0;

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
                    <StepBadge status={status} />
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
                {status === 'failed' && !isRunning && (
                  <div className="flex items-center gap-2 shrink-0" onClick={(e) => e.stopPropagation()}>
                    <button
                      onClick={() => handleRetry(step.id)}
                      disabled={retrying === step.id}
                      className="flex items-center gap-1 px-3 py-1 text-xs bg-blue-600 hover:bg-blue-700 text-white rounded-lg disabled:opacity-50 transition-colors"
                    >
                      <RotateCcw className={`w-3 h-3 ${retrying === step.id ? 'animate-spin' : ''}`} />
                      Retry
                    </button>
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

                {/* Expand toggle */}
                <div className="shrink-0 text-gray-400">
                  {isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                </div>
              </div>

              {/* Log panel */}
              {isExpanded && (
                <div className="border-t border-gray-100 dark:border-gray-700">
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
              )}
            </div>
          );
        })}
      </div>

      {/* Footer action bar */}
      <div className="px-6 py-3 border-t border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 flex items-center justify-between">
        <button
          onClick={onOpenTerminal}
          className="flex items-center gap-2 text-sm text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 transition-colors"
        >
          <Terminal className="w-4 h-4" />
          Open Terminal
        </button>
        {setupComplete && (
          <button
            onClick={() => onGoTo('complete')}
            className="px-6 py-2 bg-green-600 hover:bg-green-700 text-white font-semibold rounded-lg transition-colors"
          >
            View Summary →
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
