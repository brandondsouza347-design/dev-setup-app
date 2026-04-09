// components/Sidebar.tsx — Navigation sidebar showing step progress
import { useState } from 'react';
import { Monitor, Apple, Settings, List, Activity, CheckSquare, Home, RotateCcw, Clock, GitBranch, ChevronDown, ChevronRight, Workflow } from 'lucide-react';
import type { OsInfo, WizardPage, SetupStep, StepResult, NavSection } from '../types';
import { StepBadge } from './StepBadge';

interface Props {
  osInfo: OsInfo | null;
  page: WizardPage;
  steps: SetupStep[];
  stepResults: Record<string, StepResult>;
  currentStepIndex: number;
  setupStarted: boolean;
  historyCount: number;
  onNavigate: (page: WizardPage) => void;
}

export const Sidebar: React.FC<Props> = ({
  osInfo,
  page,
  steps,
  stepResults,
  currentStepIndex,
  setupStarted,
  historyCount,
  onNavigate,
}) => {
  const isMac = osInfo?.os === 'macos';
  const OsIcon = isMac ? Apple : Monitor;
  const osLabel = isMac
    ? `macOS${osInfo?.is_apple_silicon ? ' (M-series)' : ''}`
    : osInfo?.os === 'windows'
    ? 'Windows'
    : 'Linux';

  // Track which sections are expanded
  const [expandedSections, setExpandedSections] = useState<Set<string>>(
    new Set(['standard-workflow', 'custom-workflow'])
  );

  const toggleSection = (sectionId: string) => {
    setExpandedSections((prev) => {
      const next = new Set(prev);
      if (next.has(sectionId)) {
        next.delete(sectionId);
      } else {
        next.add(sectionId);
      }
      return next;
    });
  };

  // Define navigation structure with collapsible sections
  const navSections: NavSection[] = [
    {
      id: 'standard-workflow',
      label: 'Standard Workflow',
      children: [
        { id: 'welcome',  label: 'Welcome',   icon: <Home className="w-4 h-4" /> },
        { id: 'prereqs',  label: 'Pre-checks', icon: <CheckSquare className="w-4 h-4" /> },
        { id: 'settings', label: 'Settings',   icon: <Settings className="w-4 h-4" /> },
        { id: 'wizard',   label: 'Plan',       icon: <List className="w-4 h-4" /> },
        { id: 'progress', label: 'Progress',   icon: <Activity className="w-4 h-4" /> },
        { id: 'complete', label: 'Complete',   icon: <CheckSquare className="w-4 h-4" /> },
        { id: 'revert',   label: 'Revert',     icon: <RotateCcw className="w-4 h-4" /> },
      ],
    },
    {
      id: 'custom-workflow',
      label: 'Custom Workflow',
      children: [
        { id: 'workflow',        label: 'Workflows',       icon: <GitBranch className="w-4 h-4" /> },
        { id: 'custom-progress', label: 'Custom Progress', icon: <Workflow className="w-4 h-4" /> },
      ],
    },
  ];

  // Standalone nav item (not in a section)
  const historyNavItem = {
    id: 'history' as WizardPage,
    label: 'History',
    icon: <Clock className="w-4 h-4" />,
    badge: historyCount,
  };

  return (
    <div className="w-64 h-full flex flex-col bg-gray-900 text-gray-100 border-r border-gray-700">
      {/* App branding */}
      <div className="px-5 py-5 border-b border-gray-700">
        <div className="flex items-center gap-2 mb-1">
          <div className="w-7 h-7 rounded-lg bg-blue-600 flex items-center justify-center">
            <Activity className="w-4 h-4 text-white" />
          </div>
          <span className="font-bold text-white text-sm">Dev Setup</span>
        </div>
        <div className="flex items-center gap-1.5 text-xs text-gray-400 mt-1">
          <OsIcon className="w-3.5 h-3.5" />
          {osLabel || 'Detecting…'}
        </div>
      </div>

      {/* Navigation with collapsible sections */}
      <nav className="px-3 py-3 border-b border-gray-700">
        {/* Collapsible sections */}
        {navSections.map((section) => {
          const isExpanded = expandedSections.has(section.id);
          const hasActivePage = section.children.some((item) => item.id === page);

          return (
            <div key={section.id} className="mb-1">
              {/* Section header */}
              <button
                onClick={() => toggleSection(section.id)}
                className="w-full flex items-center gap-2 px-2 py-1.5 rounded-lg text-xs font-medium text-gray-400 hover:text-gray-300 hover:bg-gray-800 transition-colors"
              >
                {isExpanded ? (
                  <ChevronDown className="w-3.5 h-3.5" />
                ) : (
                  <ChevronRight className="w-3.5 h-3.5" />
                )}
                <span className="flex-1 text-left uppercase tracking-wide">{section.label}</span>
                {hasActivePage && !isExpanded && (
                  <span className="w-1.5 h-1.5 rounded-full bg-blue-500" />
                )}
              </button>

              {/* Section children */}
              {isExpanded && (
                <div className="ml-2 mt-0.5">
                  {section.children.map((item) => (
                    <button
                      key={item.id}
                      onClick={() => onNavigate(item.id)}
                      className={`w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-sm mb-0.5 transition-colors text-left ${
                        page === item.id
                          ? 'bg-blue-600 text-white'
                          : 'text-gray-400 hover:bg-gray-800 hover:text-white'
                      }`}
                    >
                      {item.icon}
                      <span className="flex-1">{item.label}</span>
                      {item.badge !== undefined && item.badge > 0 && (
                        <span className="px-1.5 py-0.5 text-xs rounded-full bg-gray-700 text-gray-300">
                          {item.badge}
                        </span>
                      )}
                    </button>
                  ))}
                </div>
              )}
            </div>
          );
        })}

        {/* Standalone History item */}
        <button
          onClick={() => onNavigate(historyNavItem.id)}
          className={`w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-sm mb-0.5 transition-colors text-left mt-2 ${
            page === historyNavItem.id
              ? 'bg-blue-600 text-white'
              : 'text-gray-400 hover:bg-gray-800 hover:text-white'
          }`}
        >
          {historyNavItem.icon}
          <span className="flex-1">{historyNavItem.label}</span>
          {historyNavItem.badge !== undefined && historyNavItem.badge > 0 && (
            <span className="px-1.5 py-0.5 text-xs rounded-full bg-gray-700 text-gray-300">
              {historyNavItem.badge}
            </span>
          )}
        </button>
      </nav>

      {/* Step progress list (only visible once started) */}
      {setupStarted && (
        <div className="flex-1 overflow-y-auto px-3 py-3">
          <div className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2 px-1">
            Steps
          </div>
          {steps.map((step, idx) => {
            const result = stepResults[step.id];
            const status = result?.status ?? 'pending';
            const isCurrent = idx === currentStepIndex && status === 'running';

            return (
              <div
                key={step.id}
                className={`flex items-center gap-2 px-2 py-1.5 rounded-md mb-0.5 text-xs transition-colors ${
                  isCurrent ? 'bg-blue-900/50 text-blue-300' : 'text-gray-400'
                }`}
              >
                <StatusDot status={status} />
                <span className="truncate">{step.title}</span>
                {result && <StepBadge status={status} />}
              </div>
            );
          })}
        </div>
      )}

      {/* Footer */}
      <div className="px-5 py-3 border-t border-gray-700 text-xs text-gray-500">
        v{__APP_VERSION__}
      </div>
    </div>
  );
};

const StatusDot: React.FC<{ status: string }> = ({ status }) => {
  const colors: Record<string, string> = {
    pending:  'bg-gray-600',
    running:  'bg-blue-400 animate-pulse',
    done:     'bg-green-500',
    failed:   'bg-red-500',
    skipped:  'bg-yellow-400',
  };
  return (
    <span className={`shrink-0 w-2 h-2 rounded-full ${colors[status] ?? 'bg-gray-600'}`} />
  );
};
