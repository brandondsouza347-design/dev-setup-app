// components/CustomWorkflowProgress.tsx — Live progress view for custom workflow execution
import React, { useState, useRef, useEffect } from 'react';
import {
  CheckCircle2, XCircle, Loader2, ChevronDown, ChevronRight, RotateCcw,
  ScrollText, StopCircle, Trash2, GitBranch, ArrowLeft, Settings as SettingsIcon, Globe, Edit3
} from 'lucide-react';
import type { SetupStep, StepResult, LogEntry, CustomWorkflow, StepStatus, UserConfig } from '../types';
import { StepBadge } from './StepBadge';
import { getRequiredSettings } from '../utils/stepSettings';
import { mergeWorkflowSettings, getSettingSource } from '../utils/settingsMerge';

interface Props {
  workflow: CustomWorkflow | null;
  workflowSteps: SetupStep[]; // Only steps included in the workflow
  stepResults: Record<string, StepResult>;
  logs: Record<string, LogEntry[]>;
  config: UserConfig; // Global config
  currentStepIndex: number;
  isRunning: boolean;
  workflowComplete: boolean;
  onRetry: (id: string) => Promise<void>;
  onStop: () => Promise<void>;
  onClearLogs: () => void;
  onBack: () => void;
}

type InternalLogEntry = LogEntry;

export const CustomWorkflowProgress: React.FC<Props> = ({
  workflow,
  workflowSteps,
  stepResults,
  logs,
  config,
  currentStepIndex,
  isRunning,
  workflowComplete,
  onRetry,
  onStop,
  onClearLogs,
  onBack,
}) => {
  const [expandedStep, setExpandedStep] = useState<string | null>(null);
  const [showConfig, setShowConfig] = useState(false);
  const [retrying, setRetrying] = useState<string | null>(null);
  const [logsOpen, setLogsOpen] = useState(true);
  const bottomRef = useRef<HTMLDivElement>(null);
  const logsEndRef = useRef<HTMLDivElement>(null);

  // Auto-expand the currently running step
  useEffect(() => {
    if (workflowSteps[currentStepIndex]) {
      setExpandedStep(workflowSteps[currentStepIndex].id);
    }
  }, [currentStepIndex, workflowSteps]);

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

  // Flatten + sort all log entries for workflow steps
  const allLogs: (InternalLogEntry & { stepTitle: string })[] = workflowSteps.flatMap((step) =>
    (logs[step.id] ?? []).map((entry) => ({ ...entry, stepTitle: step.title }))
  );
  allLogs.sort((a, b) => a.ts - b.ts);

  // Calculate progress stats
  const doneCount = workflowSteps.filter((s) => stepResults[s.id]?.status === 'done').length;
  const failedCount = workflowSteps.filter((s) => stepResults[s.id]?.status === 'failed').length;
  const skippedCount = workflowSteps.filter((s) => stepResults[s.id]?.status === 'skipped').length;
  const totalCount = workflowSteps.length;
  const remaining = totalCount - doneCount - failedCount - skippedCount;
  const progressPercent = totalCount > 0 ? Math.round(((doneCount + failedCount + skippedCount) / totalCount) * 100) : 0;

  const handleRetry = async (stepId: string) => {
    setRetrying(stepId);
    try {
      await onRetry(stepId);
    } finally {
      setRetrying(null);
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

  if (!workflow) {
    return (
      <div className="h-full flex items-center justify-center">
        <p className="text-gray-500">No workflow selected</p>
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col bg-gray-50 dark:bg-gray-900">
      {/* Header */}
      <div className="px-6 py-4 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700">
        <div className="flex items-start justify-between mb-3">
          <div className="flex items-center gap-3">
            <button
              onClick={onBack}
              className="p-2 text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors"
              title="Back to workflows"
            >
              <ArrowLeft className="w-5 h-5" />
            </button>
            <div>
              <div className="flex items-center gap-2">
                <GitBranch className="w-5 h-5 text-blue-600 dark:text-blue-400" />
                <h1 className="text-xl font-bold text-gray-900 dark:text-white">
                  {workflow.name}
                </h1>
              </div>
              {workflow.description && (
                <p className="text-sm text-gray-600 dark:text-gray-400 mt-1">
                  {workflow.description}
                </p>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2">
            {isRunning && (
              <button
                onClick={onStop}
                className="flex items-center gap-2 px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg transition-colors"
              >
                <StopCircle className="w-4 h-4" />
                Stop
              </button>
            )}
          </div>
        </div>

        {/* Progress bar */}
        <div className="flex items-center gap-4">
          <div className="flex-1">
            <div className="h-2 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden">
              <div
                className={`h-full transition-all duration-300 ${
                  failedCount > 0
                    ? 'bg-red-500'
                    : workflowComplete
                    ? 'bg-green-500'
                    : 'bg-blue-500'
                }`}
                style={{ width: `${progressPercent}%` }}
              />
            </div>
          </div>
          <div className="flex items-center gap-4 text-xs font-medium">
            <span className="text-gray-600 dark:text-gray-400">{progressPercent}%</span>
            <span className="text-green-600 dark:text-green-400">✓ {doneCount}</span>
            {failedCount > 0 && <span className="text-red-600 dark:text-red-400">✗ {failedCount}</span>}
            {skippedCount > 0 && <span className="text-yellow-600 dark:text-yellow-400">⊘ {skippedCount}</span>}
            {remaining > 0 && <span className="text-gray-500">⋯ {remaining}</span>}
          </div>
        </div>

        {/* Active Configuration Summary */}
        {workflow.settings && Object.keys(workflow.settings.overrides).length > 0 && (
          <div className="mt-4 border-t border-gray-200 dark:border-gray-700 pt-4">
            <button
              onClick={() => setShowConfig(!showConfig)}
              className="flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white transition-colors"
            >
              {showConfig ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
              <SettingsIcon className="w-4 h-4" />
              Active Configuration
              <span className="px-2 py-0.5 bg-blue-100 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 text-xs rounded-full">
                {Object.keys(workflow.settings.overrides).length} override{Object.keys(workflow.settings.overrides).length !== 1 ? 's' : ''}
              </span>
            </button>

            {showConfig && (
              <div className="mt-3 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
                {(() => {
                  const requiredSettings = getRequiredSettings(workflow.step_ids);
                  return Array.from(requiredSettings).map((settingKey) => {
                    const source = getSettingSource(settingKey as keyof UserConfig, workflow.settings);
                    const mergedConfig = mergeWorkflowSettings(config, workflow.settings);
                    const value = mergedConfig[settingKey as keyof UserConfig];
                    const isSensitive = settingKey.includes('password') || settingKey.includes('token') || settingKey.includes('pat');
                    const displayValue = value === null ? '(not set)' : isSensitive && value ? '••••••' : String(value);

                    return (
                      <div
                        key={settingKey}
                        className={`px-3 py-2 rounded-lg text-xs ${
                          source === 'override'
                            ? 'bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800'
                            : source === 'nullified'
                            ? 'bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700'
                            : 'bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700'
                        }`}
                      >
                        <div className="flex items-center gap-1 mb-1">
                          {source === 'override' && <Edit3 className="w-3 h-3 text-blue-600 dark:text-blue-400" />}
                          {source === 'inherited' && <Globe className="w-3 h-3 text-gray-500" />}
                          <span className="font-medium text-gray-700 dark:text-gray-300">{settingKey}</span>
                        </div>
                        <div className="text-gray-600 dark:text-gray-400 truncate">
                          {displayValue}
                        </div>
                        <div className={`text-[10px] mt-1 ${
                          source === 'override'
                            ? 'text-blue-600 dark:text-blue-400'
                            : 'text-gray-500'
                        }`}>
                          {source === 'override' ? 'Workflow override' : source === 'nullified' ? 'Disabled' : 'Global setting'}
                        </div>
                      </div>
                    );
                  });
                })()}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Main content area */}
      <div className="flex-1 overflow-y-auto px-6 py-4">
        <div className="max-w-5xl mx-auto space-y-2">
          {workflowSteps.map((step, idx) => {
            const result = stepResults[step.id];
            const status = result?.status ?? 'pending';
            const stepLogs = logs[step.id] ?? [];
            const isExpanded = expandedStep === step.id;
            const isCurrent = idx === currentStepIndex;

            return (
              <StepCard
                key={step.id}
                step={step}
                status={status}
                logs={stepLogs}
                isExpanded={isExpanded}
                isCurrent={isCurrent}
                isRetrying={retrying === step.id}
                onToggle={() => setExpandedStep(isExpanded ? null : step.id)}
                onRetry={status === 'failed' ? () => handleRetry(step.id) : undefined}
                bottomRef={isExpanded ? bottomRef : undefined}
                wasAlreadyInstalled={wasAlreadyInstalled(step.id)}
              />
            );
          })}
        </div>
      </div>

      {/* Aggregated logs panel */}
      <div className="border-t border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800">
        <button
          className="w-full flex items-center justify-between px-6 py-3 text-sm font-medium text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-750 transition-colors"
          onClick={() => setLogsOpen((o) => !o)}
        >
          <span className="flex items-center gap-2">
            <ScrollText className="w-4 h-4 text-gray-400" />
            Live Workflow Logs
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
            {logsOpen ? (
              <ChevronDown className="w-4 h-4 text-gray-400" />
            ) : (
              <ChevronRight className="w-4 h-4 text-gray-400" />
            )}
          </div>
        </button>

        {logsOpen && (
          <div className="border-t border-gray-100 dark:border-gray-700 bg-gray-950 max-h-64 overflow-y-auto font-mono text-xs px-4 py-3 space-y-0.5">
            {allLogs.length === 0 ? (
              <p className="text-gray-500 italic">No log output yet.</p>
            ) : (
              allLogs.map((entry, i) => (
                <div key={i} className="flex gap-2">
                  <span className="text-gray-600 shrink-0">[{entry.stepTitle}]</span>
                  <span className={getLogColorClass(entry.level)}>{entry.line}</span>
                </div>
              ))
            )}
            <div ref={logsEndRef} />
          </div>
        )}
      </div>
    </div>
  );
};

// ── Step card sub-component ──────────────────────────────────────────────────

interface StepCardProps {
  step: SetupStep;
  status: string;
  logs: LogEntry[];
  isExpanded: boolean;
  isCurrent: boolean;
  isRetrying: boolean;
  onToggle: () => void;
  onRetry?: () => void;
  bottomRef?: React.RefObject<HTMLDivElement>;
  wasAlreadyInstalled?: boolean;
}

const StepCard: React.FC<StepCardProps> = ({
  step,
  status,
  logs,
  isExpanded,
  isCurrent,
  isRetrying,
  onToggle,
  onRetry,
  bottomRef,
  wasAlreadyInstalled = false,
}) => {
  const StatusIcon = () => {
    if (isRetrying) return <Loader2 className="w-5 h-5 text-blue-400 animate-spin shrink-0" />;
    switch (status) {
      case 'done':
        return <CheckCircle2 className="w-5 h-5 text-green-500 shrink-0" />;
      case 'failed':
        return <XCircle className="w-5 h-5 text-red-500 shrink-0" />;
      case 'running':
        return <Loader2 className="w-5 h-5 text-blue-400 shrink-0 animate-spin" />;
      default:
        return <div className="w-5 h-5 rounded-full border-2 border-gray-300 dark:border-gray-600 shrink-0" />;
    }
  };

  const cardBg = isCurrent && status === 'running'
    ? 'bg-blue-50 dark:bg-blue-900/20 border-blue-200 dark:border-blue-800'
    : status === 'failed'
    ? 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800'
    : status === 'done'
    ? 'bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800'
    : 'bg-white dark:bg-gray-800 border-gray-200 dark:border-gray-700';

  return (
    <div className={`rounded-lg border ${cardBg} overflow-hidden transition-all`}>
      <button
        onClick={onToggle}
        className="w-full flex items-center gap-3 px-4 py-3 text-left hover:bg-black/5 dark:hover:bg-white/5 transition-colors"
      >
        <StatusIcon />
        <div className="flex-1 min-w-0">
          <div className="font-medium text-gray-900 dark:text-white">{step.title}</div>
          <div className="text-sm text-gray-600 dark:text-gray-400 truncate">{step.description}</div>
        </div>
        <div className="flex items-center gap-2">
          {status !== 'pending' && <StepBadge status={status as StepStatus} wasAlreadyInstalled={wasAlreadyInstalled} />}
          {isExpanded ? (
            <ChevronDown className="w-4 h-4 text-gray-400" />
          ) : (
            <ChevronRight className="w-4 h-4 text-gray-400" />
          )}
        </div>
      </button>

      {isExpanded && (
        <div className="border-t border-gray-200 dark:border-gray-700">
          {/* Action buttons */}
          {status === 'failed' && onRetry && (
            <div className="px-4 py-2 bg-gray-50 dark:bg-gray-900/50 flex gap-2">
              <button
                onClick={onRetry}
                disabled={isRetrying}
                className="flex items-center gap-2 px-3 py-1.5 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white text-sm rounded-lg transition-colors"
              >
                {isRetrying ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  <RotateCcw className="w-4 h-4" />
                )}
                Retry
              </button>
            </div>
          )}

          {/* Logs */}
          <div className="bg-gray-950 max-h-64 overflow-y-auto font-mono text-xs px-4 py-3 space-y-0.5">
            {logs.length === 0 ? (
              <p className="text-gray-500 italic">No logs for this step yet.</p>
            ) : (
              logs.map((entry, i) => (
                <div key={i} className={getLogColorClass(entry.level)}>
                  {entry.line}
                </div>
              ))
            )}
            {bottomRef && <div ref={bottomRef} />}
          </div>
        </div>
      )}
    </div>
  );
};

// ── Helper functions ──────────────────────────────────────────────────────────

function getLogColorClass(level: string): string {
  switch (level) {
    case 'error':
      return 'text-red-400';
    case 'warn':
      return 'text-yellow-400';
    case 'success':
      return 'text-green-400';
    default:
      return 'text-gray-300';
  }
}
