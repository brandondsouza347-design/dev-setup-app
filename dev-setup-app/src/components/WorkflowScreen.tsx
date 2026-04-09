// components/WorkflowScreen.tsx — Custom workflow creation and management
import React, { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import {
  ChevronLeft, Plus, Play, Save, Trash2, Edit2,
  X, Check, AlertCircle, Clock, Shield, Settings as SettingsIcon
} from 'lucide-react';
import type { CustomWorkflow, SetupStep, UserConfig } from '../types';
import type { WorkflowSettings } from '../utils/settingsMerge';
import { isAdminStep, hasAdminSteps } from '../utils/adminSteps';
import { WorkflowSettingsEditor } from './WorkflowSettingsEditor';

interface Props {
  steps: SetupStep[];
  config: UserConfig;
  onBack: () => void;
  onExecuteWorkflow: (workflow: CustomWorkflow) => void;
}

export const WorkflowScreen: React.FC<Props> = ({ steps, config, onBack, onExecuteWorkflow }) => {
  const [workflows, setWorkflows] = useState<CustomWorkflow[]>([]);
  const [selectedSteps, setSelectedSteps] = useState<string[]>([]);
  const [workflowName, setWorkflowName] = useState('');
  const [workflowDescription, setWorkflowDescription] = useState('');
  const [workflowSettings, setWorkflowSettings] = useState<WorkflowSettings>({
    overrides: {},
    nullify: [],
  });
  const [editingWorkflow, setEditingWorkflow] = useState<CustomWorkflow | null>(null);
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [activeTab, setActiveTab] = useState<'steps' | 'settings'>('steps');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    loadWorkflows();
  }, []);

  const loadWorkflows = async () => {
    try {
      const list = await invoke<CustomWorkflow[]>('list_workflows');
      setWorkflows(list);
    } catch (err) {
      console.error('Failed to load workflows:', err);
    }
  };

  const handleSaveWorkflow = async () => {
    if (!workflowName.trim() || selectedSteps.length === 0) {
      alert('Please provide a name and select at least one step');
      return;
    }

    setLoading(true);
    try {
      const workflowId = editingWorkflow?.id || `wf_${Date.now()}`;
      await invoke('save_workflow', {
        workflowId,
        name: workflowName.trim(),
        description: workflowDescription.trim(),
        stepIds: selectedSteps,
        settings: workflowSettings,
      });

      await loadWorkflows();
      resetForm();
      alert('Workflow saved successfully!');
    } catch (err) {
      alert(`Failed to save workflow: ${err}`);
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteWorkflow = async (workflowId: string) => {
    if (!confirm('Are you sure you want to delete this workflow?')) return;

    try {
      await invoke('delete_workflow', { workflowId });
      await loadWorkflows();
    } catch (err) {
      alert(`Failed to delete workflow: ${err}`);
    }
  };

  const handleEditWorkflow = (workflow: CustomWorkflow) => {
    setEditingWorkflow(workflow);
    setWorkflowName(workflow.name);
    setWorkflowDescription(workflow.description);
    setSelectedSteps(workflow.step_ids);
    setWorkflowSettings(workflow.settings || { overrides: {}, nullify: [] });
    setShowCreateForm(true);
  };

  const handleExecute = (workflow: CustomWorkflow) => {
    onExecuteWorkflow(workflow);
  };

  const toggleStepSelection = (stepId: string) => {
    setSelectedSteps(prev =>
      prev.includes(stepId)
        ? prev.filter(id => id !== stepId)
        : [...prev, stepId]
    );
  };

  const moveStep = (index: number, direction: 'up' | 'down') => {
    const newSteps = [...selectedSteps];
    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= newSteps.length) return;

    [newSteps[index], newSteps[targetIndex]] = [newSteps[targetIndex], newSteps[index]];
    setSelectedSteps(newSteps);
  };

  const resetForm = () => {
    setWorkflowName('');
    setWorkflowDescription('');
    setSelectedSteps([]);
    setWorkflowSettings({ overrides: {}, nullify: [] });
    setEditingWorkflow(null);
    setShowCreateForm(false);
    setActiveTab('steps');
  };

  const getStepById = (stepId: string) => steps.find(s => s.id === stepId);

  return (
    <div className="flex flex-col h-full p-8 overflow-y-auto">
      {/* Header */}
      <div className="mb-6">
        <button
          onClick={onBack}
          className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 mb-4"
        >
          <ChevronLeft className="w-4 h-4" /> Back
        </button>
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white">Custom Workflows</h2>
        <p className="text-gray-500 dark:text-gray-400 mt-1">
          Create and manage custom step sequences for your development setup
        </p>
      </div>

      {/* Create New Workflow Button */}
      {!showCreateForm && (
        <button
          onClick={() => setShowCreateForm(true)}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg mb-6 w-fit transition-colors"
        >
          <Plus className="w-4 h-4" />
          Create New Workflow
        </button>
      )}

      {/* Workflow Creation Form */}
      {showCreateForm && (
        <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-6 mb-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              {editingWorkflow ? 'Edit Workflow' : 'Create New Workflow'}
            </h3>
            <button onClick={resetForm} className="text-gray-500 hover:text-gray-700">
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Basic Info */}
          <div className="space-y-4 mb-6">
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Workflow Name *
              </label>
              <input
                type="text"
                value={workflowName}
                onChange={(e) => setWorkflowName(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
                placeholder="e.g., Backend Only Setup"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Description (Optional)
              </label>
              <textarea
                value={workflowDescription}
                onChange={(e) => setWorkflowDescription(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
                placeholder="Describe what this workflow does..."
                rows={2}
              />
            </div>
          </div>

          {/* Tabs */}
          <div className="border-b border-gray-200 dark:border-gray-700 mb-4">
            <div className="flex gap-4">
              <button
                onClick={() => setActiveTab('steps')}
                className={`px-4 py-2 font-medium text-sm border-b-2 transition-colors ${
                  activeTab === 'steps'
                    ? 'border-blue-600 text-blue-600 dark:text-blue-400'
                    : 'border-transparent text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300'
                }`}
              >
                Steps ({selectedSteps.length})
              </button>
              <button
                onClick={() => setActiveTab('settings')}
                className={`px-4 py-2 font-medium text-sm border-b-2 transition-colors flex items-center gap-2 ${
                  activeTab === 'settings'
                    ? 'border-blue-600 text-blue-600 dark:text-blue-400'
                    : 'border-transparent text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300'
                }`}
              >
                <SettingsIcon className="w-4 h-4" />
                Settings
                {(workflowSettings.overrides && Object.keys(workflowSettings.overrides).length > 0) && (
                  <span className="px-1.5 py-0.5 bg-blue-100 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 text-xs rounded-full">
                    {Object.keys(workflowSettings.overrides).length}
                  </span>
                )}
              </button>
            </div>
          </div>

          {/* Tab Content */}
          <div className="space-y-4">
            {activeTab === 'steps' && (
              <>
                    {/* Step Selection */}
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Select Steps (click to add/remove)
                  </label>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-2 max-h-80 overflow-y-auto border border-gray-200 dark:border-gray-700 rounded-lg p-4">
                    {steps.map((step) => {
                      const requiresAdmin = isAdminStep(step.id);
                      return (
                        <button
                          key={step.id}
                          onClick={() => toggleStepSelection(step.id)}
                          className={`text-left px-3 py-2 rounded-lg border transition-colors ${
                            selectedSteps.includes(step.id)
                              ? 'bg-blue-50 dark:bg-blue-900/20 border-blue-500 text-blue-700 dark:text-blue-300'
                              : 'bg-gray-50 dark:bg-gray-700 border-gray-200 dark:border-gray-600 hover:bg-gray-100 dark:hover:bg-gray-600'
                          }`}
                        >
                          <div className="flex items-center gap-2">
                            {selectedSteps.includes(step.id) && <Check className="w-4 h-4" />}
                            <span className="text-sm font-medium flex-1">{step.title}</span>
                            {requiresAdmin && (
                              <span title="Requires admin privileges">
                                <Shield className="w-4 h-4 text-amber-500" />
                              </span>
                            )}
                          </div>
                        </button>
                      );
                    })}
                  </div>
                </div>

                {/* Selected Steps Order */}
                {selectedSteps.length > 0 && (
                  <div>
                    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                      Execution Order (use arrows to reorder)
                    </label>
                    <div className="space-y-2">
                      {selectedSteps.map((stepId, index) => {
                        const step = getStepById(stepId);
                        return step ? (
                          <div
                            key={stepId}
                            className="flex items-center gap-2 p-3 bg-gray-50 dark:bg-gray-700 rounded-lg border border-gray-200 dark:border-gray-600"
                          >
                            <span className="text-sm font-medium text-gray-500 dark:text-gray-400 w-8">
                              {index + 1}.
                            </span>
                            <span className="flex-1 text-sm text-gray-900 dark:text-white">
                              {step.title}
                            </span>
                            <div className="flex items-center gap-1">
                              <button
                                onClick={() => moveStep(index, 'up')}
                                disabled={index === 0}
                                className="p-1 text-gray-500 hover:text-gray-700 disabled:opacity-30 disabled:cursor-not-allowed"
                              >
                                ↑
                              </button>
                              <button
                                onClick={() => moveStep(index, 'down')}
                                disabled={index === selectedSteps.length - 1}
                                className="p-1 text-gray-500 hover:text-gray-700 disabled:opacity-30 disabled:cursor-not-allowed"
                              >
                                ↓
                              </button>
                              <button
                                onClick={() => toggleStepSelection(stepId)}
                                className="p-1 text-red-500 hover:text-red-700"
                              >
                                <X className="w-4 h-4" />
                              </button>
                            </div>
                          </div>
                        ) : null;
                      })}
                    </div>
                  </div>
                )}
              </>
            )}

            {activeTab === 'settings' && (
              <WorkflowSettingsEditor
                stepIds={selectedSteps}
                globalConfig={config}
                workflowSettings={workflowSettings}
                onUpdateSettings={setWorkflowSettings}
              />
            )}
          </div>

          <div className="flex items-center gap-2 pt-4">
            <button
              onClick={handleSaveWorkflow}
              disabled={loading || !workflowName.trim() || selectedSteps.length === 0}
              className="flex items-center gap-2 px-4 py-2 bg-green-600 hover:bg-green-700 disabled:bg-gray-400 text-white rounded-lg transition-colors"
            >
              <Save className="w-4 h-4" />
              {loading ? 'Saving...' : 'Save Workflow'}
            </button>
            <button
              onClick={resetForm}
              className="px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* Saved Workflows List */}
      <div>
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
          Saved Workflows ({workflows.length})
        </h3>

        {workflows.length === 0 ? (
          <div className="text-center py-12 bg-gray-50 dark:bg-gray-800 rounded-xl border border-dashed border-gray-300 dark:border-gray-600">
            <AlertCircle className="w-12 h-12 text-gray-400 mx-auto mb-3" />
            <p className="text-gray-500 dark:text-gray-400">
              No workflows created yet. Click "Create New Workflow" to get started.
            </p>
          </div>
        ) : (
          <div className="space-y-4">
            {workflows.map((workflow) => {
              const requiresAdmin = hasAdminSteps(workflow.step_ids);
              return (
                <div
                  key={workflow.id}
                  className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-5 hover:shadow-md transition-shadow"
                >
                  <div className="flex items-start justify-between mb-3">
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <h4 className="text-lg font-semibold text-gray-900 dark:text-white">
                          {workflow.name}
                        </h4>
                        {requiresAdmin && (
                          <span className="flex items-center gap-1 px-2 py-0.5 bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 text-xs font-medium rounded-full">
                            <Shield className="w-3 h-3" />
                            Requires Admin
                          </span>
                        )}
                        {workflow.settings && Object.keys(workflow.settings.overrides).length > 0 && (
                          <span className="flex items-center gap-1 px-2 py-0.5 bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400 text-xs font-medium rounded-full">
                            <SettingsIcon className="w-3 h-3" />
                            {Object.keys(workflow.settings.overrides).length} override{Object.keys(workflow.settings.overrides).length !== 1 ? 's' : ''}
                          </span>
                        )}
                      </div>
                      {workflow.description && (
                        <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
                          {workflow.description}
                        </p>
                      )}
                      <div className="flex items-center gap-4 mt-2 text-xs text-gray-500 dark:text-gray-400">
                        <span>{workflow.step_ids.length} steps</span>
                        <span className="flex items-center gap-1">
                          <Clock className="w-3 h-3" />
                          Created {new Date(workflow.created_at * 1000).toLocaleDateString()}
                        </span>
                        {workflow.last_run_at && (
                          <span>Last run {new Date(workflow.last_run_at * 1000).toLocaleDateString()}</span>
                        )}
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center gap-2 ml-4">
                    <button
                      onClick={() => handleExecute(workflow)}
                      className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                    >
                      <Play className="w-4 h-4" />
                      Run
                    </button>
                    <button
                      onClick={() => handleEditWorkflow(workflow)}
                      className="p-2 text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100"
                      title="Edit workflow"
                    >
                      <Edit2 className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => handleDeleteWorkflow(workflow.id)}
                      className="p-2 text-red-600 hover:text-red-700"
                      title="Delete workflow"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>

                  {/* Step List Preview */}
                  <div className="mt-3 pt-3 border-t border-gray-200 dark:border-gray-700">
                    <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-2">Steps:</p>
                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
                      {workflow.step_ids.map((stepId, idx) => {
                        const step = getStepById(stepId);
                        return step ? (
                          <div key={stepId} className="flex items-center gap-2 text-xs text-gray-600 dark:text-gray-300">
                            <span className="text-gray-400">{idx + 1}.</span>
                            <span className="truncate">{step.title}</span>
                          </div>
                        ) : null;
                      })}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};
