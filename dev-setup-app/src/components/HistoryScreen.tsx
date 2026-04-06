// components/HistoryScreen.tsx — Display past setup/revert run history
import { useState } from 'react';
import {
  Clock, CheckCircle, XCircle, AlertCircle, Trash2, ChevronDown, ChevronRight,
  ListChecks, CalendarClock
} from 'lucide-react';
import type { RunHistory } from '../types';

interface Props {
  history: RunHistory[];
  onClearSelected: (ids: string[]) => Promise<void>;
  onRefresh: () => Promise<void>;
}

export const HistoryScreen: React.FC<Props> = ({ history, onClearSelected, onRefresh }) => {
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());
  const [clearing, setClearing] = useState(false);

  const handleToggleSelect = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const handleToggleExpand = (id: string) => {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const handleSelectAll = () => {
    if (selectedIds.size === history.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(history.map((h) => h.id)));
    }
  };

  const handleClearSelected = async () => {
    if (selectedIds.size === 0) return;
    setClearing(true);
    try {
      await onClearSelected(Array.from(selectedIds));
      setSelectedIds(new Set());
      await onRefresh();
    } finally {
      setClearing(false);
    }
  };

  const formatTimestamp = (ts: number) => {
    const date = new Date(ts * 1000);
    return date.toLocaleString([], {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const formatDuration = (started: number, completed: number) => {
    const durationSecs = completed - started;
    if (durationSecs < 60) return `${durationSecs}s`;
    const mins = Math.floor(durationSecs / 60);
    const secs = durationSecs % 60;
    return `${mins}m ${secs}s`;
  };

  // Empty state
  if (history.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-full py-16 px-8 text-center">
        <CalendarClock className="w-12 h-12 text-gray-400 mb-4" />
        <h2 className="text-xl font-semibold text-gray-700 dark:text-gray-200 mb-2">
          No Run History Yet
        </h2>
        <p className="text-gray-500 dark:text-gray-400 max-w-sm">
          Once you complete a setup or revert operation, the history will appear here.
        </p>
      </div>
    );
  }

  // Sort history by completed_at descending (most recent first)
  const sortedHistory = [...history].sort((a, b) => b.completed_at - a.completed_at);

  return (
    <div className="h-full flex flex-col overflow-hidden">
      {/* Header */}
      <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="font-bold text-gray-900 dark:text-white">Run History</h2>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {history.length} {history.length === 1 ? 'run' : 'runs'} recorded (last 20)
            </p>
          </div>
          <div className="flex items-center gap-3">
            <button
              onClick={handleSelectAll}
              className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white transition-colors"
            >
              <ListChecks className="w-4 h-4" />
              {selectedIds.size === history.length ? 'Deselect All' : 'Select All'}
            </button>
            {selectedIds.size > 0 && (
              <button
                onClick={handleClearSelected}
                disabled={clearing}
                className="flex items-center gap-2 px-3 py-1.5 text-sm bg-red-600 hover:bg-red-700 disabled:bg-red-400 text-white rounded-lg transition-colors"
              >
                <Trash2 className="w-4 h-4" />
                Clear Selected ({selectedIds.size})
              </button>
            )}
          </div>
        </div>
      </div>

      {/* History list */}
      <div className="flex-1 overflow-y-auto px-6 py-4 space-y-3">
        {sortedHistory.map((run) => (
          <RunHistoryCard
            key={run.id}
            run={run}
            selected={selectedIds.has(run.id)}
            expanded={expandedIds.has(run.id)}
            onToggleSelect={() => handleToggleSelect(run.id)}
            onToggleExpand={() => handleToggleExpand(run.id)}
            formatTimestamp={formatTimestamp}
            formatDuration={formatDuration}
          />
        ))}
      </div>
    </div>
  );
};

// ─── Run History Card ────────────────────────────────────────────────────────

interface RunHistoryCardProps {
  run: RunHistory;
  selected: boolean;
  expanded: boolean;
  onToggleSelect: () => void;
  onToggleExpand: () => void;
  formatTimestamp: (ts: number) => string;
  formatDuration: (started: number, completed: number) => string;
}

const RunHistoryCard: React.FC<RunHistoryCardProps> = ({
  run,
  selected,
  expanded,
  onToggleSelect,
  onToggleExpand,
  formatTimestamp,
  formatDuration,
}) => {
  const StatusIcon = () => {
    switch (run.status) {
      case 'success':
        return <CheckCircle className="w-5 h-5 text-green-500" />;
      case 'failed':
        return <XCircle className="w-5 h-5 text-red-500" />;
      case 'cancelled':
        return <AlertCircle className="w-5 h-5 text-yellow-500" />;
      default:
        return <Clock className="w-5 h-5 text-gray-400" />;
    }
  };

  const statusBg =
    run.status === 'success'
      ? 'border-green-200 dark:border-green-800 bg-green-50/30 dark:bg-green-900/10'
      : run.status === 'failed'
      ? 'border-red-200 dark:border-red-700 bg-red-50/30 dark:bg-red-900/10'
      : 'border-yellow-200 dark:border-yellow-700 bg-yellow-50/30 dark:bg-yellow-900/10';

  const typeColor =
    run.run_type === 'setup'
      ? 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300'
      : 'bg-amber-100 dark:bg-amber-900 text-amber-700 dark:text-amber-300';

  return (
    <div className={`rounded-lg border ${statusBg} overflow-hidden`}>
      <div className="flex items-center gap-3 px-4 py-3">
        {/* Selection checkbox */}
        <input
          type="checkbox"
          checked={selected}
          onChange={onToggleSelect}
          className="w-4 h-4 accent-red-600 cursor-pointer"
          onClick={(e) => e.stopPropagation()}
        />

        {/* Status icon */}
        <StatusIcon />

        {/* Main content */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className={`px-2 py-0.5 text-xs font-semibold rounded ${typeColor}`}>
              {run.run_type.toUpperCase()}
            </span>
            <span className="text-xs text-gray-500 dark:text-gray-400">
              {formatTimestamp(run.completed_at)}
            </span>
            <span className="text-xs text-gray-400">•</span>
            <span className="text-xs text-gray-500 dark:text-gray-400">
              {formatDuration(run.started_at, run.completed_at)}
            </span>
          </div>
          <div className="flex items-center gap-3 text-sm text-gray-600 dark:text-gray-300">
            <span>
              {run.step_count} {run.step_count === 1 ? 'step' : 'steps'}
            </span>
            {run.failed_steps.length > 0 && (
              <>
                <span className="text-gray-400">•</span>
                <span className="text-red-600 dark:text-red-400 font-medium">
                  {run.failed_steps.length} failed
                </span>
              </>
            )}
          </div>
        </div>

        {/* Expand toggle (if has failed steps) */}
        {run.failed_steps.length > 0 && (
          <button
            onClick={onToggleExpand}
            className="p-1 hover:bg-gray-200 dark:hover:bg-gray-700 rounded transition-colors"
          >
            {expanded ? (
              <ChevronDown className="w-4 h-4 text-gray-500" />
            ) : (
              <ChevronRight className="w-4 h-4 text-gray-500" />
            )}
          </button>
        )}
      </div>

      {/* Expanded failed steps */}
      {expanded && run.failed_steps.length > 0 && (
        <div className="border-t border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3">
          <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-200 mb-2">
            Failed Steps:
          </h4>
          <div className="space-y-3">
            {run.failed_steps.map((failedStep, idx) => (
              <div
                key={idx}
                className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg"
              >
                <div className="flex items-start gap-2 mb-1">
                  <XCircle className="w-4 h-4 text-red-500 shrink-0 mt-0.5" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-red-700 dark:text-red-300">
                      {failedStep.step_name}
                    </p>
                    {failedStep.error_message && (
                      <p className="text-xs text-red-600 dark:text-red-400 mt-1">
                        {failedStep.error_message}
                      </p>
                    )}
                  </div>
                </div>
                {/* Failed step logs */}
                {failedStep.logs.length > 0 && (
                  <div className="mt-2 p-2 bg-gray-950 rounded font-mono text-xs max-h-32 overflow-y-auto">
                    {failedStep.logs.map((log, logIdx) => (
                      <div key={logIdx} className="text-red-400 leading-relaxed">
                        {log}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
