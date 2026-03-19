// components/WizardStepList.tsx — Step overview / confirmation before running
import { Clock, ChevronLeft, Play, AlertTriangle } from 'lucide-react';
import type { SetupStep, StepResult, UserConfig, WizardPage, OsInfo } from '../types';
import { StepBadge } from './StepBadge';

interface Props {
  steps: SetupStep[];
  stepResults: Record<string, StepResult>;
  config: UserConfig;
  osInfo: OsInfo | null;
  isRunning: boolean;
  onStart: () => void;
  onBack: (page: WizardPage) => void;
  onSkip: (id: string) => void;
}

export const WizardStepList: React.FC<Props> = ({
  steps,
  stepResults,
  config,
  osInfo,
  isRunning,
  onStart,
  onBack,
  onSkip,
}) => {
  const totalMinutes = steps
    .filter((s) => stepResults[s.id]?.status !== 'skipped')
    .reduce((acc, s) => acc + s.estimated_minutes, 0);

  const isWindows = osInfo?.os === 'windows';
  const tarMissing = isWindows && !config.wsl_tar_path;

  return (
    <div className="flex flex-col h-full p-8">
      <div className="mb-6">
        <button
          onClick={() => onBack('settings')}
          className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 mb-4"
        >
          <ChevronLeft className="w-4 h-4" /> Back to Settings
        </button>
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white">Setup Plan</h2>
        <p className="text-gray-500 dark:text-gray-400 mt-1">
          Review the steps below. Uncheck optional ones to skip them.
        </p>
      </div>

      {/* Warning: missing WSL TAR */}
      {tarMissing && (
        <div className="mb-4 flex items-start gap-3 p-4 bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800 rounded-lg">
          <AlertTriangle className="w-5 h-5 text-yellow-600 shrink-0 mt-0.5" />
          <div className="text-sm text-yellow-800 dark:text-yellow-200">
            <strong>WSL TAR path not set.</strong> The "Import Ubuntu 22.04" step will fail without
            it. Go back to Settings and set the path to your{' '}
            <code>ubuntu_22.04_modified.tar</code> file.
          </div>
        </div>
      )}

      {/* Steps list */}
      <div className="flex-1 overflow-y-auto space-y-2">
        {steps.map((step, idx) => {
          const result = stepResults[step.id];
          const isSkipped = result?.status === 'skipped';

          return (
            <div
              key={step.id}
              className={`flex items-center gap-4 p-4 rounded-lg border transition-colors ${
                isSkipped
                  ? 'bg-gray-50 dark:bg-gray-900 border-gray-200 dark:border-gray-700 opacity-50'
                  : 'bg-white dark:bg-gray-800 border-gray-200 dark:border-gray-700'
              }`}
            >
              {/* Step number */}
              <div className="w-7 h-7 rounded-full bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300 text-xs font-bold flex items-center justify-center shrink-0">
                {idx + 1}
              </div>

              {/* Info */}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-medium text-gray-900 dark:text-white text-sm">{step.title}</span>
                  {!step.required && (
                    <span className="text-xs text-gray-400 bg-gray-100 dark:bg-gray-700 px-2 py-0.5 rounded-full">
                      optional
                    </span>
                  )}
                  {result && <StepBadge status={result.status} />}
                </div>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5 truncate">{step.description}</p>
              </div>

              {/* Time estimate */}
              <div className="flex items-center gap-1 text-xs text-gray-400 shrink-0">
                <Clock className="w-3 h-3" />
                ~{step.estimated_minutes}m
              </div>

              {/* Skip toggle (optional steps only, before running) */}
              {!step.required && !isRunning && (
                <button
                  onClick={() => onSkip(step.id)}
                  className={`text-xs px-3 py-1 rounded-full border transition-colors ${
                    isSkipped
                      ? 'border-blue-400 text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/20'
                      : 'border-gray-300 text-gray-500 hover:bg-gray-50 dark:hover:bg-gray-700'
                  }`}
                >
                  {isSkipped ? 'Un-skip' : 'Skip'}
                </button>
              )}
            </div>
          );
        })}
      </div>

      {/* Footer */}
      <div className="flex items-center justify-between mt-6 pt-4 border-t border-gray-200 dark:border-gray-700">
        <div className="flex items-center gap-2 text-sm text-gray-500">
          <Clock className="w-4 h-4" />
          Estimated total: ~{totalMinutes} minutes
        </div>
        <button
          onClick={onStart}
          disabled={isRunning || tarMissing}
          className="flex items-center gap-2 px-6 py-3 bg-green-600 hover:bg-green-700 disabled:bg-gray-300 text-white font-bold rounded-xl transition-colors shadow-md"
        >
          <Play className="w-5 h-5" />
          {isRunning ? 'Running…' : 'Start Setup'}
        </button>
      </div>
    </div>
  );
};
