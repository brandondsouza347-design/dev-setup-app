// components/StepBadge.tsx — Small status badge for a step
import type { StepStatus } from '../types';

interface Props {
  status: StepStatus;
  small?: boolean;
  wasAlreadyInstalled?: boolean;
}

const config: Record<StepStatus, { label: string; classes: string }> = {
  pending:  { label: 'Pending',  classes: 'bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400' },
  running:  { label: 'Running',  classes: 'bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300 animate-pulse' },
  done:     { label: '✓ Done',   classes: 'bg-green-100 dark:bg-green-900 text-green-700 dark:text-green-300' },
  failed:   { label: '✗ Failed', classes: 'bg-red-100 dark:bg-red-900 text-red-700 dark:text-red-300' },
  skipped:  { label: 'Skipped',  classes: 'bg-yellow-100 dark:bg-yellow-900 text-yellow-700 dark:text-yellow-300' },
};

export const StepBadge: React.FC<Props> = ({ status, small = true, wasAlreadyInstalled = false }) => {
  const { label, classes } = config[status];
  // Override label if already installed
  const displayLabel = (status === 'done' && wasAlreadyInstalled) ? 'Already installed ✓' : label;

  return (
    <span className={`inline-block rounded-full font-medium ${small ? 'text-xs px-2 py-0.5' : 'text-sm px-3 py-1'} ${classes}`}>
      {displayLabel}
    </span>
  );
};
