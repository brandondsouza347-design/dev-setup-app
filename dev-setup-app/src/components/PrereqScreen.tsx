// components/PrereqScreen.tsx — Pre-flight checks before setup
import React, { useEffect } from 'react';
import { CheckCircle, XCircle, RefreshCw, ChevronRight, ChevronLeft } from 'lucide-react';
import type { PrereqCheck, WizardPage } from '../types';

interface Props {
  checks: PrereqCheck[];
  onCheck: () => Promise<void>;
  onNext: (page: WizardPage) => void;
  onBack: () => void;
}

export const PrereqScreen: React.FC<Props> = ({ checks, onCheck, onNext, onBack }) => {
  const [checking, setChecking] = React.useState(false);

  useEffect(() => {
    runChecks();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const runChecks = async () => {
    setChecking(true);
    try {
      await onCheck();
    } finally {
      setChecking(false);
    }
  };

  const allPassed = checks.length > 0 && checks.every((c) => c.passed);
  const hasFailures = checks.some((c) => !c.passed);

  return (
    <div className="flex flex-col h-full p-8">
      <div className="mb-6">
        <button onClick={onBack} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 mb-4">
          <ChevronLeft className="w-4 h-4" /> Back
        </button>
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white">Pre-flight Checks</h2>
        <p className="text-gray-500 dark:text-gray-400 mt-1">
          Verifying your system is ready before starting the setup.
        </p>
      </div>

      {/* Check results */}
      <div className="flex-1 space-y-3">
        {checking && checks.length === 0 && (
          <div className="flex items-center gap-3 text-gray-500">
            <RefreshCw className="w-5 h-5 animate-spin" />
            Running checks…
          </div>
        )}
        {checks.map((check) => (
          <div
            key={check.name}
            className={`flex items-start gap-3 p-4 rounded-lg border ${
              check.passed
                ? 'bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800'
                : 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800'
            }`}
          >
            {check.passed ? (
              <CheckCircle className="w-5 h-5 text-green-500 mt-0.5 shrink-0" />
            ) : (
              <XCircle className="w-5 h-5 text-red-500 mt-0.5 shrink-0" />
            )}
            <div>
              <div className="font-medium text-gray-900 dark:text-white">{check.name}</div>
              <div className="text-sm text-gray-600 dark:text-gray-400">{check.message}</div>
            </div>
          </div>
        ))}
      </div>

      {/* Warning for failures */}
      {hasFailures && (
        <div className="mt-4 p-4 bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800 rounded-lg">
          <p className="text-sm text-yellow-800 dark:text-yellow-200">
            ⚠️ Some checks failed. You can still proceed but certain steps may fail.
            Fix the issues above and re-run checks for best results.
          </p>
        </div>
      )}

      {/* Footer */}
      <div className="flex items-center justify-between mt-6 pt-4 border-t border-gray-200 dark:border-gray-700">
        <button
          onClick={runChecks}
          disabled={checking}
          className="flex items-center gap-2 px-4 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 disabled:opacity-50 transition-colors"
        >
          <RefreshCw className={`w-4 h-4 ${checking ? 'animate-spin' : ''}`} />
          Re-run Checks
        </button>
        <button
          onClick={() => onNext('settings')}
          disabled={checking}
          className="flex items-center gap-2 px-6 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-300 text-white font-semibold rounded-lg transition-colors"
        >
          {allPassed ? 'Continue' : 'Continue Anyway'}
          <ChevronRight className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};
