// components/HistoryScreen.tsx — Display past setup/revert run history
import { useState, useMemo } from 'react';
import {
 Clock, CheckCircle, XCircle, AlertCircle, Trash2, ChevronDown, ChevronRight,
  ListChecks, CalendarClock, Download, SkipForward
} from 'lucide-react';
import { save } from '@tauri-apps/plugin-dialog';
import { writeTextFile } from '@tauri-apps/plugin-fs';
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

  const handleExtractLogs = async (run: RunHistory) => {
    const timestamp = new Date(run.completed_at * 1000).toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const defaultName = `dev-setup-${run.run_type}-${timestamp}.txt`;

    try {
      const filePath = await save({
        defaultPath: defaultName,
        filters: [{ name: 'Text Files', extensions: ['txt'] }],
      });

      if (!filePath) {
        console.log('User cancelled file save dialog');
        return;
      }

      const passedCount = run.step_count - run.failed_steps.length - (run.skipped_steps?.length ?? 0);

      let content = `Dev Setup App - ${run.run_type.toUpperCase()} Run Log\n`;
      content += `=`.repeat(60) + '\n\n';
      content += `Started: ${formatTimestamp(run.started_at)}\n`;
      content += `Completed: ${formatTimestamp(run.completed_at)}\n`;
      content += `Duration: ${formatDuration(run.started_at, run.completed_at)}\n`;
      content += `Status: ${run.status.toUpperCase()}\n`;
      content += `\n`;
      content += `Total Steps: ${run.step_count}\n`;
      content += `  Passed: ${passedCount}\n`;
      content += `  Failed: ${run.failed_steps.length}\n`;
      content += `  Skipped: ${run.skipped_steps?.length ?? 0}\n`;
      content += `\n` + `=`.repeat(60) + `\n\n`;

      if (run.failed_steps.length > 0) {
        content += `FAILED STEPS:\n` + `-`.repeat(60) + `\n\n`;
        run.failed_steps.forEach((step, idx) => {
          content += `${idx + 1}. ❌ ${step.step_name}\n`;
          if (step.error_message) content += `   Error: ${step.error_message}\n`;
          if (step.logs.length > 0) {
            content += `   Logs:\n`;
            step.logs.forEach(log => content += `     ${log}\n`);
          }
          content += `\n`;
        });
      }

      if (run.skipped_steps && run.skipped_steps.length > 0) {
        content += `SKIPPED STEPS:\n` + `-`.repeat(60) + `\n\n`;
        run.skipped_steps.forEach((step, idx) => {
          content += `${idx + 1}. ⏭️  ${step.step_name}\n`;
        });
        content += `\n`;
      }

      console.log('Writing log file to:', filePath);
      await writeTextFile(filePath, content);
      console.log('Log file written successfully');
      alert(`Logs saved to:\n${filePath}`);
    } catch (error) {
      console.error('Failed to save logs:', error);
      alert(`Failed to save logs: ${error}`);
    }
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

  // Group history by run_type and sort each group by completed_at descending
  const groupedHistory = useMemo(() => {
    const groups: { workflow: RunHistory[]; setup: RunHistory[]; revert: RunHistory[] } = {
      workflow: [],
      setup: [],
      revert: [],
    };

    history.forEach((run) => {
      if (run.run_type === 'workflow') {
        groups.workflow.push(run);
      } else if (run.run_type === 'revert') {
        groups.revert.push(run);
      } else {
        groups.setup.push(run);
      }
    });

    // Sort each group by completed_at descending
    groups.workflow.sort((a, b) => b.completed_at - a.completed_at);
    groups.setup.sort((a, b) => b.completed_at - a.completed_at);
    groups.revert.sort((a, b) => b.completed_at - a.completed_at);

    return groups;
  }, [history]);

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
            {selectedIds.size === 1 && (
              <button
                onClick={() => {
                  const selectedRun = history.find(h => selectedIds.has(h.id));
                  if (selectedRun) handleExtractLogs(selectedRun);
                }}
                className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
              >
                <Download className="w-4 h-4" />
                Extract Logs
              </button>
            )}
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

      {/* History list - grouped by run type */}
      <div className="flex-1 overflow-y-auto px-6 py-4 space-y-6">
        {/* Workflow Runs Section */}
        {groupedHistory.workflow.length > 0 && (
          <div>
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-purple-500"></div>
              Custom Workflows ({groupedHistory.workflow.length})
            </h3>
            <div className="space-y-3">
              {groupedHistory.workflow.map((run) => (
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
        )}

        {/* Standard Setup Runs Section */}
        {groupedHistory.setup.length > 0 && (
          <div>
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-blue-500"></div>
              Standard Setup ({groupedHistory.setup.length})
            </h3>
            <div className="space-y-3">
              {groupedHistory.setup.map((run) => (
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
        )}

        {/* Revert Operations Section */}
        {groupedHistory.revert.length > 0 && (
          <div>
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-amber-500"></div>
              Revert Operations ({groupedHistory.revert.length})
            </h3>
            <div className="space-y-3">
              {groupedHistory.revert.map((run) => (
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
        )}

        {/* Empty state */}
        {history.length === 0 && (
          <div className="flex flex-col items-center justify-center py-12 text-gray-500 dark:text-gray-400">
            <Clock className="w-12 h-12 mb-3" />
            <p>No run history yet</p>
          </div>
        )}
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
    run.run_type === 'workflow'
      ? 'bg-purple-100 dark:bg-purple-900 text-purple-700 dark:text-purple-300'
      : run.run_type === 'setup'
      ? 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300'
      : 'bg-amber-100 dark:bg-amber-900 text-amber-700 dark:text-amber-300';

  const typeLabel =
    run.run_type === 'workflow' && run.workflow_name
      ? run.workflow_name
      : run.run_type.toUpperCase();

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
              {typeLabel}
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
            <span className="flex items-center gap-1">
              <CheckCircle className="w-3.5 h-3.5 text-green-500" />
              {run.step_count - run.failed_steps.length - (run.skipped_steps?.length ?? 0)} passed
            </span>
            {run.failed_steps.length > 0 && (
              <span className="flex items-center gap-1 text-red-600 dark:text-red-400 font-medium">
                <XCircle className="w-3.5 h-3.5" />
                {run.failed_steps.length} failed
              </span>
            )}
            {run.skipped_steps && run.skipped_steps.length > 0 && (
              <span className="flex items-center gap-1 text-yellow-600 dark:text-yellow-400">
                <SkipForward className="w-3.5 h-3.5" />
                {run.skipped_steps.length} skipped
              </span>
            )}
          </div>
        </div>

        {/* Expand toggle (if has failed or skipped steps) */}
        {(run.failed_steps.length > 0 || (run.skipped_steps && run.skipped_steps.length > 0)) && (
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

      {/* Expanded failed and skipped steps */}
      {expanded && (run.failed_steps.length > 0 || (run.skipped_steps && run.skipped_steps.length > 0)) && (
        <div className="border-t border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 space-y-4">
          {/* Failed Steps Section */}
          {run.failed_steps.length > 0 && (
            <div>
              <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-200 mb-2">
                Failed Steps:
              </h4>
              <div className="space-y-3">{run.failed_steps.map((failedStep, idx) => (
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

          {/* Skipped Steps Section */}
          {run.skipped_steps && run.skipped_steps.length > 0 && (
            <div>
              <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-200 mb-2">
                Skipped Steps:
              </h4>
              <div className="space-y-2">
                {run.skipped_steps.map((skippedStep, idx) => (
                  <div
                    key={idx}
                    className="p-3 bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800 rounded-lg"
                  >
                    <div className="flex items-start gap-2">
                      <SkipForward className="w-4 h-4 text-yellow-500 shrink-0 mt-0.5" />
                      <p className="text-sm font-medium text-yellow-700 dark:text-yellow-300">
                        {skippedStep.step_name}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
