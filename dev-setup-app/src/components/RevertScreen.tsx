// components/RevertScreen.tsx — Safely revert the Windows WSL environment to clean state
import { useState } from 'react';
import { AlertTriangle, RotateCcw, ChevronDown, ChevronRight, CheckCircle, XCircle, Loader, Circle, ShieldAlert } from 'lucide-react';
import type { OsInfo, SetupStep, StepResult, LogEntry } from '../types';

interface Props {
  osInfo: OsInfo | null;
  revertSteps: SetupStep[];
  revertResults: Record<string, StepResult>;
  logs: Record<string, LogEntry[]>;
  isReverting: boolean;
  revertComplete: boolean;
  onStartRevert: () => Promise<void>;
  onRetryStep: (id: string) => Promise<void>;
  onReset: () => void;
}

export const RevertScreen: React.FC<Props> = ({
  osInfo,
  revertSteps,
  revertResults,
  logs,
  isReverting,
  revertComplete,
  onStartRevert,
  onRetryStep,
  onReset,
}) => {
  const [confirmed, setConfirmed] = useState(false);
  const [expandedSteps, setExpandedSteps] = useState<Set<string>>(new Set());

  const isWindows = osInfo?.os === 'windows';
  const hasStarted = isReverting || Object.keys(revertResults).length > 0;

  const toggleExpand = (id: string) => {
    setExpandedSteps((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  // ── macOS guard ────────────────────────────────────────────────────────────
  if (!isWindows) {
    return (
      <div className="flex flex-col items-center justify-center h-full py-16 px-8 text-center">
        <ShieldAlert className="w-12 h-12 text-gray-400 mb-4" />
        <h2 className="text-xl font-semibold text-gray-700 dark:text-gray-200 mb-2">
          Not Available on macOS
        </h2>
        <p className="text-gray-500 dark:text-gray-400 max-w-sm">
          The Revert tool removes the Windows WSL environment and is only applicable on Windows.
        </p>
      </div>
    );
  }

  // ── Complete state ────────────────────────────────────────────────────────
  if (revertComplete) {
    const anyFailed = revertSteps.some((s) => revertResults[s.id]?.status === 'failed');
    return (
      <div className="flex flex-col items-center justify-center h-full py-16 px-8 text-center">
        {anyFailed ? (
          <XCircle className="w-14 h-14 text-red-500 mb-4" />
        ) : (
          <CheckCircle className="w-14 h-14 text-green-500 mb-4" />
        )}
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-3">
          {anyFailed ? 'Revert Partially Complete' : 'Revert Complete'}
        </h2>
        {!anyFailed ? (
          <>
            <p className="text-gray-600 dark:text-gray-300 max-w-md mb-2">
              Your WSL environment has been removed and Windows has been reverted to its base state.
            </p>
            <p className="text-amber-600 dark:text-amber-400 font-medium">
              ⚠ Please restart your PC to fully apply the feature removal.
            </p>
          </>
        ) : (
          <p className="text-gray-600 dark:text-gray-300 max-w-md">
            Some steps could not be completed. Review the steps below and retry failed ones.
          </p>
        )}
        <div className="flex gap-3 mt-8">
          <button
            onClick={onReset}
            className="px-5 py-2 border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800 rounded-lg text-sm transition-colors"
          >
            Start Over
          </button>
        </div>
        {/* Step summary */}
        <div className="mt-8 w-full max-w-lg text-left space-y-2">
          {revertSteps.map((step) => {
            const result = revertResults[step.id];
            const status = result?.status ?? 'pending';
            return (
              <StepRow
                key={step.id}
                step={step}
                status={status}
                logs={logs[step.id] ?? []}
                expanded={expandedSteps.has(step.id)}
                onToggle={() => toggleExpand(step.id)}
                onRetry={status === 'failed' ? () => onRetryStep(step.id) : undefined}
              />
            );
          })}
        </div>
      </div>
    );
  }

  // ── Active / running state ────────────────────────────────────────────────
  if (hasStarted) {
    const doneCount = revertSteps.filter(
      (s) => revertResults[s.id]?.status === 'done'
    ).length;
    const failedStep = revertSteps.find((s) => revertResults[s.id]?.status === 'failed');

    return (
      <div className="h-full flex flex-col overflow-hidden">
        {/* Header */}
        <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-amber-50 dark:bg-amber-900/20">
          <div className="flex items-center gap-3">
            <RotateCcw className="w-5 h-5 text-amber-600 dark:text-amber-400" />
            <div>
              <h2 className="font-semibold text-gray-900 dark:text-white">
                Reverting WSL Environment
              </h2>
              <p className="text-sm text-gray-500 dark:text-gray-400">
                {isReverting
                  ? `Step ${doneCount + 1} of ${revertSteps.length} running…`
                  : failedStep
                  ? `Stopped — step failed: ${failedStep.title}`
                  : `${doneCount} / ${revertSteps.length} complete`}
              </p>
            </div>
          </div>
        </div>

        {/* Steps */}
        <div className="flex-1 overflow-y-auto px-6 py-4 space-y-3">
          {revertSteps.map((step) => {
            const result = revertResults[step.id];
            const status = result?.status ?? 'pending';
            return (
              <StepRow
                key={step.id}
                step={step}
                status={status}
                logs={logs[step.id] ?? []}
                expanded={expandedSteps.has(step.id)}
                onToggle={() => toggleExpand(step.id)}
                onRetry={status === 'failed' ? () => onRetryStep(step.id) : undefined}
              />
            );
          })}
        </div>
      </div>
    );
  }

  // ── Confirmation state (default) ──────────────────────────────────────────
  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-6 py-10">

        {/* Warning banner */}
        <div className="flex gap-4 p-5 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-700 rounded-xl mb-6">
          <AlertTriangle className="w-7 h-7 text-red-500 shrink-0 mt-0.5" />
          <div>
            <h2 className="text-lg font-bold text-red-700 dark:text-red-400 mb-1">
              Revert to Clean Windows State
            </h2>
            <p className="text-sm text-red-600 dark:text-red-300">
              This will <strong>permanently delete</strong> your WSL environment and all files
              inside ERC Ubuntu.
            </p>
          </div>
        </div>

        {/* Backup guarantee callout */}
        <div className="flex gap-4 p-5 bg-amber-50 dark:bg-amber-900/20 border-2 border-amber-400 dark:border-amber-600 rounded-xl mb-8">
          <ShieldAlert className="w-6 h-6 text-amber-600 dark:text-amber-400 shrink-0 mt-0.5" />
          <div className="text-sm">
            <p className="font-bold text-amber-800 dark:text-amber-300 mb-1">
              Backup is mandatory — deletion is blocked until it succeeds
            </p>
            <p className="text-amber-700 dark:text-amber-400 mb-2">
              Before any data is removed, the ERC distro is exported to{' '}
              <code className="bg-amber-100 dark:bg-amber-800 px-1 rounded">%USERPROFILE%\WSL_Backup\</code>.
              The script verifies the file exists on disk and is a valid non-empty TAR.
              If the backup cannot be confirmed, <strong>the revert stops immediately</strong> and
              nothing is deleted.
            </p>
            <p className="text-amber-700 dark:text-amber-400">
              To restore after revert:{' '}
              <code className="text-xs bg-amber-100 dark:bg-amber-800 px-1.5 py-0.5 rounded block mt-1">
                wsl --import ERC &lt;install-dir&gt; %USERPROFILE%\WSL_Backup\erc_backup_*.tar --version 2
              </code>
            </p>
          </div>
        </div>

        {/* What will happen */}
        <div className="mb-8">
          <h3 className="text-sm font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-4">
            What will be reverted
          </h3>
          <div className="space-y-3">
            {revertSteps.map((step, i) => (
              <div
                key={step.id}
                className="flex gap-3 p-3.5 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg"
              >
                <span className="shrink-0 w-6 h-6 rounded-full bg-amber-100 dark:bg-amber-900 text-amber-700 dark:text-amber-300 flex items-center justify-center text-xs font-bold">
                  {i + 1}
                </span>
                <div>
                  <div className="font-medium text-gray-900 dark:text-white text-sm">
                    {step.title}
                    {!step.required && (
                      <span className="ml-2 text-xs text-gray-400 font-normal">(optional)</span>
                    )}
                  </div>
                  <div className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                    {step.description}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Confirmation checkbox */}
        <label className="flex items-start gap-3 cursor-pointer mb-8 select-none">
          <input
            type="checkbox"
            checked={confirmed}
            onChange={(e) => setConfirmed(e.target.checked)}
            className="mt-0.5 w-4 h-4 accent-red-600 cursor-pointer"
          />
          <span className="text-sm text-gray-700 dark:text-gray-300">
            I understand that a <strong>verified backup will be created first</strong> and that,
            once the backup is confirmed on disk, my WSL environment will be{' '}
            <strong>permanently deleted</strong>. I have saved any important work inside the ERC distro.
          </span>
        </label>

        {/* Action button */}
        <button
          onClick={onStartRevert}
          disabled={!confirmed}
          className="flex items-center justify-center gap-2 w-full py-3 px-6 bg-red-600 hover:bg-red-700 disabled:bg-gray-300 dark:disabled:bg-gray-700 disabled:cursor-not-allowed text-white font-semibold rounded-xl transition-colors shadow-md"
        >
          <RotateCcw className="w-5 h-5" />
          Begin Revert
        </button>
        {!confirmed && (
          <p className="text-center text-xs text-gray-400 mt-2">
            Check the box above to enable the revert button
          </p>
        )}
      </div>
    </div>
  );
};

// ── Step row sub-component ────────────────────────────────────────────────────

interface StepRowProps {
  step: SetupStep;
  status: string;
  logs: LogEntry[];
  expanded: boolean;
  onToggle: () => void;
  onRetry?: () => void;
}

const StepRow: React.FC<StepRowProps> = ({ step, status, logs, expanded, onToggle, onRetry }) => {
  const StatusIcon = () => {
    switch (status) {
      case 'done':    return <CheckCircle className="w-4 h-4 text-green-500 shrink-0" />;
      case 'failed':  return <XCircle className="w-4 h-4 text-red-500 shrink-0" />;
      case 'running': return <Loader className="w-4 h-4 text-blue-400 shrink-0 animate-spin" />;
      default:        return <Circle className="w-4 h-4 text-gray-400 shrink-0" />;
    }
  };

  const rowBg =
    status === 'running' ? 'border-blue-300 dark:border-blue-600 bg-blue-50/50 dark:bg-blue-900/10' :
    status === 'done'    ? 'border-green-200 dark:border-green-800 bg-green-50/30 dark:bg-green-900/10' :
    status === 'failed'  ? 'border-red-200 dark:border-red-700 bg-red-50/30 dark:bg-red-900/10' :
    'border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800';

  return (
    <div className={`rounded-lg border ${rowBg} overflow-hidden`}>
      <button
        onClick={onToggle}
        className="w-full flex items-center gap-3 px-4 py-3 text-left"
      >
        <StatusIcon />
        <span className="flex-1 text-sm font-medium text-gray-900 dark:text-white truncate">
          {step.title}
        </span>
        <span className="text-xs text-gray-400 mr-1">
          {status === 'running' ? 'Running…' :
           status === 'done'    ? '✓ Done' :
           status === 'failed'  ? '✗ Failed' :
           status === 'skipped' ? '⏭ Skipped' : 'Pending'}
        </span>
        {logs.length > 0 && (
          expanded
            ? <ChevronDown className="w-3.5 h-3.5 text-gray-400 shrink-0" />
            : <ChevronRight className="w-3.5 h-3.5 text-gray-400 shrink-0" />
        )}
      </button>

      {/* Log output */}
      {expanded && logs.length > 0 && (
        <div className="border-t border-gray-200 dark:border-gray-700 bg-gray-950 px-4 py-3 max-h-48 overflow-y-auto font-mono text-xs leading-relaxed">
          {logs.map((entry, i) => {
            const color =
              entry.level === 'error'   ? 'text-red-400' :
              entry.level === 'warn'    ? 'text-yellow-400' :
              entry.level === 'success' ? 'text-green-400' :
              'text-gray-300';
            return (
              <div key={i} className={color}>
                {entry.line}
              </div>
            );
          })}
        </div>
      )}

      {/* Retry button */}
      {onRetry && (
        <div className="border-t border-red-200 dark:border-red-700 px-4 py-2 bg-red-50/50 dark:bg-red-900/10">
          <button
            onClick={onRetry}
            className="text-xs text-red-600 dark:text-red-400 hover:underline font-medium"
          >
            Retry this step
          </button>
        </div>
      )}
    </div>
  );
};
