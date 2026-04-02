// App.tsx — Root component: wires the wizard pages together
import { useSetup } from './hooks/useSetup';
import { Sidebar } from './components/Sidebar';
import { WelcomeScreen } from './components/WelcomeScreen';
import { PrereqScreen } from './components/PrereqScreen';
import { SettingsScreen } from './components/SettingsScreen';
import { WizardStepList } from './components/WizardStepList';
import { ProgressDashboard } from './components/ProgressDashboard';
import { CompleteScreen } from './components/CompleteScreen';
import { RevertScreen } from './components/RevertScreen';

function App() {
  const setup = useSetup();

  // Cast logs to the expected shape for ProgressDashboard
  const logsForDashboard = setup.logs;

  return (
    <div className="flex h-screen bg-gray-50 dark:bg-gray-900 text-gray-900 dark:text-white overflow-hidden">
      {/* Sidebar */}
      <Sidebar
        osInfo={setup.osInfo}
        page={setup.page}
        steps={setup.steps}
        stepResults={setup.stepResults}
        currentStepIndex={setup.currentStepIndex}
        setupStarted={setup.setupStarted}
        onNavigate={setup.setPage}
      />

      {/* Main content area */}
      <main className="flex-1 overflow-hidden">
        {setup.page === 'welcome' && (
          <div className="h-full overflow-y-auto">
            <WelcomeScreen osInfo={setup.osInfo} onNext={setup.setPage} />
          </div>
        )}

        {setup.page === 'prereqs' && (
          <div className="h-full overflow-y-auto">
            <PrereqScreen
              checks={setup.prereqChecks}
              onCheck={setup.runPrereqCheck}
              onNext={setup.setPage}
              onBack={() => setup.setPage('welcome')}
              isWindows={setup.osInfo?.os === 'windows'}
              adminAgentStatus={setup.adminAgentStatus}
              adminAgentError={setup.adminAgentError}
              adminAgentLogs={setup.adminAgentLogs}
              onRequestAdminAgent={setup.requestAdminAgent}
              onShutdownAdminAgent={setup.shutdownAdminAgent}
              onPrereqAction={setup.handlePrereqAction}
              config={setup.config}
              onUpdateConfig={setup.updateConfig}
              onSaveConfig={setup.saveConfig}
              prereqLogs={setup.prereqLogs}
              onClearPrereqLogs={setup.clearPrereqLogs}
            />
          </div>
        )}

        {setup.page === 'settings' && (
          <div className="h-full overflow-y-auto">
            <SettingsScreen
              config={setup.config}
              osInfo={setup.osInfo}
              onUpdate={setup.updateConfig}
              onSave={setup.saveConfig}
              onNext={setup.setPage}
              onBack={() => setup.setPage('prereqs')}
            />
          </div>
        )}

        {setup.page === 'wizard' && (
          <div className="h-full overflow-y-auto">
            <WizardStepList
              steps={setup.steps}
              stepResults={setup.stepResults}
              config={setup.config}
              osInfo={setup.osInfo}
              isRunning={setup.isRunning}
              onStart={setup.startSetup}
              onBack={setup.setPage}
              onSkip={setup.skipStep}
            />
          </div>
        )}

        {setup.page === 'progress' && (
          <ProgressDashboard
            steps={setup.steps}
            revertSteps={setup.revertSteps}
            stepResults={setup.stepResults}
            logs={logsForDashboard}
            currentStepIndex={setup.currentStepIndex}
            isRunning={setup.isRunning}
            isRollingBackStep={setup.isRollingBackStep}
            setupComplete={setup.setupComplete}
            onRetry={setup.retryStep}
            onRevertStep={setup.revertStep}
            onSkip={setup.skipStep}
            onContinue={setup.resumeSetup}
            onOpenTerminal={setup.openTerminal}
            onStop={setup.stopSetup}
            onGoTo={setup.setPage}
            onClearLogs={setup.clearLogs}
          />
        )}

        {setup.page === 'complete' && (
          <div className="h-full overflow-y-auto">
            <CompleteScreen
              steps={setup.steps}
              stepResults={setup.stepResults}
              osInfo={setup.osInfo}
              onReset={setup.resetSetup}
              onOpenTerminal={setup.openTerminal}
            />
          </div>
        )}

        {setup.page === 'revert' && (
          <div className="h-full overflow-hidden flex flex-col">
            <RevertScreen
              osInfo={setup.osInfo}
              revertSteps={setup.revertSteps}
              revertResults={setup.revertResults}
              logs={setup.logs}
              isReverting={setup.isReverting}
              revertComplete={setup.revertComplete}
              onStartRevert={setup.startRevert}
              onRetryStep={setup.retryRevertStep}
              onReset={setup.resetRevert}
            />
          </div>
        )}
      </main>
    </div>
  );
}

export default App;
