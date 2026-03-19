// components/CompleteScreen.tsx — Setup completion screen with summary
import {
  PartyPopper, CheckCircle2, XCircle, SkipForward,
  RotateCcw, ExternalLink, Terminal
} from 'lucide-react';
import type { SetupStep, StepResult, OsInfo } from '../types';

interface Props {
  steps: SetupStep[];
  stepResults: Record<string, StepResult>;
  osInfo: OsInfo | null;
  onReset: () => void;
  onOpenTerminal: () => void;
}

export const CompleteScreen: React.FC<Props> = ({
  steps,
  stepResults,
  osInfo,
  onReset,
  onOpenTerminal,
}) => {
  const done    = steps.filter((s) => stepResults[s.id]?.status === 'done');
  const failed  = steps.filter((s) => stepResults[s.id]?.status === 'failed');
  const skipped = steps.filter((s) => stepResults[s.id]?.status === 'skipped');

  const allGood = failed.length === 0;
  const isMac   = osInfo?.os === 'macos';

  const nextSteps = isMac
    ? [
        'Restart your terminal or run: source ~/.zshrc',
        'Open your project: code /path/to/project',
        'Select Python interpreter in VS Code: ⇧⌘P → Python: Select Interpreter',
        'Connect to PostgreSQL: psql -U postgres -d dev_db',
        'Test Redis: redis-cli ping  (should return PONG)',
      ]
    : [
        'Restart your computer if prompted by the WSL install',
        'Open WSL: Start Menu → Ubuntu-22.04 or run wsl',
        'Open project in VS Code: Ctrl+Shift+P → Remote-WSL: Open Folder in WSL',
        'Add your SSH public key to GitHub: github.com/settings/ssh',
        'Test connection: wsl -d Ubuntu-22.04 -- ssh -T git@github.com',
      ];

  return (
    <div className="flex flex-col items-center justify-center min-h-full py-12 px-8 text-center">
      {/* Header */}
      <div className="mb-8">
        <div className={`inline-flex items-center justify-center w-20 h-20 rounded-2xl ${allGood ? 'bg-green-500' : 'bg-yellow-500'} text-white mb-4 shadow-lg`}>
          {allGood ? <PartyPopper className="w-10 h-10" /> : <CheckCircle2 className="w-10 h-10" />}
        </div>
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white">
          {allGood ? 'Setup Complete! 🎉' : 'Setup Finished with Issues'}
        </h1>
        <p className="mt-2 text-gray-500 dark:text-gray-400 max-w-lg">
          {allGood
            ? 'Your development environment is ready to use.'
            : `${done.length} steps succeeded, ${failed.length} failed. You can retry failed steps.`}
        </p>
      </div>

      {/* Step summary grid */}
      <div className="w-full max-w-lg mb-8 grid grid-cols-3 gap-3 text-sm">
        <SummaryCard icon={<CheckCircle2 className="w-5 h-5 text-green-500" />} count={done.length} label="Completed" color="green" />
        <SummaryCard icon={<XCircle className="w-5 h-5 text-red-500" />} count={failed.length} label="Failed" color="red" />
        <SummaryCard icon={<SkipForward className="w-5 h-5 text-yellow-500" />} count={skipped.length} label="Skipped" color="yellow" />
      </div>

      {/* Failed steps list */}
      {failed.length > 0 && (
        <div className="w-full max-w-lg mb-8 text-left bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-xl p-4">
          <h3 className="font-semibold text-red-700 dark:text-red-300 mb-2">Failed Steps</h3>
          <ul className="space-y-1">
            {failed.map((s) => (
              <li key={s.id} className="text-sm text-red-600 dark:text-red-400">
                ✗ {s.title}: {stepResults[s.id]?.error ?? 'Unknown error'}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Next steps */}
      <div className="w-full max-w-lg mb-8 text-left">
        <h3 className="text-sm font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-3">
          Next Steps
        </h3>
        <ol className="space-y-2">
          {nextSteps.map((step, i) => (
            <li key={i} className="flex items-start gap-3 text-sm text-gray-700 dark:text-gray-300">
              <span className="w-5 h-5 rounded-full bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300 text-xs font-bold flex items-center justify-center shrink-0 mt-0.5">
                {i + 1}
              </span>
              {step}
            </li>
          ))}
        </ol>
      </div>

      {/* Actions */}
      <div className="flex flex-col gap-3 w-full max-w-md">
        <button
          onClick={onOpenTerminal}
          className="flex items-center justify-center gap-2 w-full py-3 px-6 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-xl transition-colors shadow-md"
        >
          <Terminal className="w-5 h-5" />
          Open Terminal
        </button>
        <a
          href="https://code.visualstudio.com/"
          target="_blank"
          rel="noreferrer"
          className="flex items-center justify-center gap-2 w-full py-2 px-6 border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800 rounded-xl transition-colors text-sm"
        >
          <ExternalLink className="w-4 h-4" />
          VS Code Documentation
        </a>
        <button
          onClick={onReset}
          className="flex items-center justify-center gap-2 w-full py-2 px-6 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors text-sm"
        >
          <RotateCcw className="w-4 h-4" />
          Run Setup Again
        </button>
      </div>
    </div>
  );
};

// ─── Sub-component ─────────────────────────────────────────────────────────

const colorMap: Record<string, string> = {
  green:  'bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800',
  red:    'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800',
  yellow: 'bg-yellow-50 dark:bg-yellow-900/20 border-yellow-200 dark:border-yellow-800',
};

const SummaryCard: React.FC<{ icon: React.ReactNode; count: number; label: string; color: string }> = ({
  icon, count, label, color
}) => (
  <div className={`flex flex-col items-center p-4 rounded-xl border ${colorMap[color]}`}>
    {icon}
    <span className="text-2xl font-bold text-gray-900 dark:text-white mt-1">{count}</span>
    <span className="text-xs text-gray-500">{label}</span>
  </div>
);
