// components/WorkflowSettingsEditor.tsx — Dynamic settings editor for custom workflows
import React, { useState } from 'react';
import { Settings as SettingsIcon, ChevronDown, ChevronRight, Info, Globe, Edit3, XCircle } from 'lucide-react';
import type { UserConfig } from '../types';
import type { WorkflowSettings } from '../utils/settingsMerge';
import {
  getRequiredSettings,
  groupSettingsByCategory,
  SettingCategory,
  SETTING_LABELS,
  SETTING_DESCRIPTIONS,
} from '../utils/stepSettings';
import { getWorkflowSettingsSummary } from '../utils/settingsMerge';

interface Props {
  stepIds: string[];
  globalConfig: UserConfig;
  workflowSettings: WorkflowSettings;
  onUpdateSettings: (settings: WorkflowSettings) => void;
}

type SettingMode = 'inherit' | 'override' | 'nullify';

export const WorkflowSettingsEditor: React.FC<Props> = ({
  stepIds,
  globalConfig,
  workflowSettings,
  onUpdateSettings,
}) => {
  const [expandedCategories, setExpandedCategories] = useState<Set<SettingCategory>>(
    new Set([SettingCategory.Git, SettingCategory.Tenant])
  );

  // Get required settings and group by category
  const requiredSettings = getRequiredSettings(stepIds);
  const groupedSettings = groupSettingsByCategory(requiredSettings);

  // Get summary
  const summary = getWorkflowSettingsSummary(requiredSettings, workflowSettings);

  const toggleCategory = (category: SettingCategory) => {
    setExpandedCategories((prev) => {
      const next = new Set(prev);
      if (next.has(category)) {
        next.delete(category);
      } else {
        next.add(category);
      }
      return next;
    });
  };

  const getSettingMode = (settingKey: keyof UserConfig): SettingMode => {
    if (workflowSettings.nullify.includes(settingKey)) {
      return 'nullify';
    }
    if (settingKey in workflowSettings.overrides) {
      return 'override';
    }
    return 'inherit';
  };

  const handleModeChange = (settingKey: keyof UserConfig, mode: SettingMode) => {
    const updated = { ...workflowSettings };

    // Remove from all states first
    delete updated.overrides[settingKey];
    updated.nullify = updated.nullify.filter((k) => k !== settingKey);

    if (mode === 'override') {
      // Set override to current global value as starting point
      updated.overrides[settingKey] = globalConfig[settingKey] as any;
    } else if (mode === 'nullify') {
      updated.nullify.push(settingKey);
    }
    // mode === 'inherit' means do nothing (already removed from both)

    onUpdateSettings(updated);
  };

  const handleOverrideValueChange = (settingKey: keyof UserConfig, value: string | boolean) => {
    const updated = { ...workflowSettings };
    updated.overrides[settingKey] = value as any;
    onUpdateSettings(updated);
  };

  if (requiredSettings.size === 0) {
    return (
      <div className="text-center py-12 bg-gray-50 dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
        <SettingsIcon className="w-12 h-12 text-gray-400 mx-auto mb-3" />
        <p className="text-gray-600 dark:text-gray-400">
          No settings required for the selected steps.
        </p>
        <p className="text-sm text-gray-500 dark:text-gray-500 mt-1">
          This workflow will use global settings by default.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Summary Card */}
      <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4">
        <div className="flex items-start gap-3">
          <Info className="w-5 h-5 text-blue-600 dark:text-blue-400 shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="text-sm font-medium text-blue-900 dark:text-blue-100">
              {summary.total} setting{summary.total !== 1 ? 's' : ''} required by selected steps
            </p>
            <div className="flex items-center gap-4 mt-2 text-xs">
              {summary.inherited > 0 && (
                <span className="flex items-center gap-1 text-gray-600 dark:text-gray-400">
                  <Globe className="w-3 h-3" />
                  {summary.inherited} inherited
                </span>
              )}
              {summary.overridden > 0 && (
                <span className="flex items-center gap-1 text-blue-600 dark:text-blue-400">
                  <Edit3 className="w-3 h-3" />
                  {summary.overridden} overridden
                </span>
              )}
              {summary.nullified > 0 && (
                <span className="flex items-center gap-1 text-gray-500">
                  <XCircle className="w-3 h-3" />
                  {summary.nullified} disabled
                </span>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Settings by Category */}
      {Array.from(groupedSettings.entries()).map(([category, settings]) => {
        const isExpanded = expandedCategories.has(category);

        return (
          <div
            key={category}
            className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg overflow-hidden"
          >
            {/* Category Header */}
            <button
              onClick={() => toggleCategory(category)}
              className="w-full flex items-center justify-between px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-750 transition-colors"
            >
              <div className="flex items-center gap-2">
                {isExpanded ? (
                  <ChevronDown className="w-4 h-4 text-gray-500" />
                ) : (
                  <ChevronRight className="w-4 h-4 text-gray-500" />
                )}
                <span className="font-medium text-gray-900 dark:text-white">{category}</span>
                <span className="px-2 py-0.5 text-xs rounded-full bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400">
                  {settings.size}
                </span>
              </div>
            </button>

            {/* Settings List */}
            {isExpanded && (
              <div className="border-t border-gray-200 dark:border-gray-700 divide-y divide-gray-100 dark:divide-gray-700">
                {Array.from(settings).map((settingKey) => (
                  <SettingRow
                    key={settingKey}
                    settingKey={settingKey}
                    globalValue={globalConfig[settingKey]}
                    mode={getSettingMode(settingKey)}
                    overrideValue={workflowSettings.overrides[settingKey]}
                    onModeChange={(mode) => handleModeChange(settingKey, mode)}
                    onOverrideValueChange={(value) => handleOverrideValueChange(settingKey, value)}
                  />
                ))}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

// ── Setting Row Sub-component ──────────────────────────────────────────────────

interface SettingRowProps {
  settingKey: keyof UserConfig;
  globalValue: any;
  mode: SettingMode;
  overrideValue: any;
  onModeChange: (mode: SettingMode) => void;
  onOverrideValueChange: (value: string | boolean) => void;
}

const SettingRow: React.FC<SettingRowProps> = ({
  settingKey,
  globalValue,
  mode,
  overrideValue,
  onModeChange,
  onOverrideValueChange,
}) => {
  const label = SETTING_LABELS[settingKey] || settingKey;
  const description = SETTING_DESCRIPTIONS[settingKey];
  const isBoolean = typeof globalValue === 'boolean';
  const isSensitive =
    settingKey.includes('password') ||
    settingKey.includes('secret') ||
    settingKey.includes('token') ||
    settingKey.includes('pat');

  const displayGlobalValue = isSensitive && globalValue
    ? '••••••••'
    : globalValue?.toString() || '(not set)';

  return (
    <div className="px-4 py-4">
      {/* Setting Label */}
      <div className="mb-3">
        <label className="block text-sm font-medium text-gray-900 dark:text-white mb-1">
          {label}
        </label>
        {description && (
          <p className="text-xs text-gray-500 dark:text-gray-400">{description}</p>
        )}
      </div>

      {/* Mode Selection */}
      <div className="space-y-2">
        {/* Inherit Option */}
        <label className="flex items-start gap-2 cursor-pointer">
          <input
            type="radio"
            checked={mode === 'inherit'}
            onChange={() => onModeChange('inherit')}
            className="mt-0.5 w-4 h-4 text-blue-600"
          />
          <div className="flex-1">
            <span className="text-sm text-gray-700 dark:text-gray-300">
              Inherit from global
            </span>
            <div className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
              Using: <span className="font-mono">{displayGlobalValue}</span>
            </div>
          </div>
        </label>

        {/* Override Option */}
        <label className="flex items-start gap-2 cursor-pointer">
          <input
            type="radio"
            checked={mode === 'override'}
            onChange={() => onModeChange('override')}
            className="mt-0.5 w-4 h-4 text-blue-600"
          />
          <div className="flex-1">
            <span className="text-sm text-gray-700 dark:text-gray-300">
              Override with custom value
            </span>
            {mode === 'override' && (
              <div className="mt-2">
                {isBoolean ? (
                  <label className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      checked={!!overrideValue}
                      onChange={(e) => onOverrideValueChange(e.target.checked)}
                      className="w-4 h-4 text-blue-600"
                    />
                    <span className="text-sm text-gray-600 dark:text-gray-400">
                      {overrideValue ? 'Enabled' : 'Disabled'}
                    </span>
                  </label>
                ) : (
                  <input
                    type={isSensitive ? 'password' : 'text'}
                    value={overrideValue?.toString() || ''}
                    onChange={(e) => onOverrideValueChange(e.target.value)}
                    className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white text-sm"
                    placeholder={`Enter custom ${label.toLowerCase()}`}
                  />
                )}
              </div>
            )}
          </div>
        </label>

        {/* Nullify Option */}
        <label className="flex items-start gap-2 cursor-pointer">
          <input
            type="radio"
            checked={mode === 'nullify'}
            onChange={() => onModeChange('nullify')}
            className="mt-0.5 w-4 h-4 text-blue-600"
          />
          <div className="flex-1">
            <span className="text-sm text-gray-700 dark:text-gray-300">
              Not needed for this workflow
            </span>
            <div className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
              Step scripts will receive null/empty value
            </div>
          </div>
        </label>
      </div>
    </div>
  );
};
