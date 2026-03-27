// App.tsx — Root component: wires the wizard pages together
import { useSetup } from './hooks/useSetup';
import { Sidebar } from './components/Sidebar';
import { WelcomeScreen } from './components/WelcomeScreen';
import { PrereqScreen } from './components/PrereqScreen';
import { SettingsScreen } from './components/SettingsScreen';
import { WizardStepList } from './components/WizardStepList';
import { ProgressDashboard } from './components/ProgressDashboard';
import { CompleteScreen } from './components/CompleteScreen';

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
            stepResults={setup.stepResults}
            logs={logsForDashboard}
            currentStepIndex={setup.currentStepIndex}
            isRunning={setup.isRunning}
            setupComplete={setup.setupComplete}
            onRetry={setup.retryStep}
            onSkip={setup.skipStep}
            onOpenTerminal={setup.openTerminal}
            onGoTo={setup.setPage}
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
      </main>
    </div>
  );
}

export default App;
