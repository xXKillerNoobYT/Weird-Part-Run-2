/**
 * CompanionsPage — "What should I also order?" system.
 *
 * Three internal sub-tabs:
 * 1. Suggestions — pending suggestion board + history
 * 2. Link Rules — CRUD for category-level companion rules
 * 3. What Should I Also Order? — manual trigger form
 *
 * KPI stats bar sits above all tabs, always visible.
 */

import { useState } from 'react';
import { Lightbulb, BookOpen, HelpCircle } from 'lucide-react';
import { CompanionStats } from '../components/companions/CompanionStats';
import { SuggestionBoard } from '../components/companions/SuggestionBoard';
import { RulesPanel } from '../components/companions/RulesPanel';
import { ManualTriggerPanel } from '../components/companions/ManualTriggerPanel';

type SubTab = 'suggestions' | 'rules' | 'trigger';

const SUB_TABS: { id: SubTab; label: string; icon: React.ElementType }[] = [
  { id: 'suggestions', label: 'Suggestions', icon: Lightbulb },
  { id: 'rules', label: 'Link Rules', icon: BookOpen },
  { id: 'trigger', label: 'What Should I Also Order?', icon: HelpCircle },
];

export function CompanionsPage() {
  const [activeTab, setActiveTab] = useState<SubTab>('suggestions');

  return (
    <div className="flex flex-col h-full overflow-hidden">
      {/* Stats KPI row — always visible */}
      <div className="px-4 sm:px-6 pt-4 pb-2 flex-shrink-0">
        <CompanionStats />
      </div>

      {/* Sub-tab bar */}
      <div className="px-4 sm:px-6 flex-shrink-0">
        <div className="border-b border-gray-200 dark:border-gray-700">
          <nav className="-mb-px flex gap-4 overflow-x-auto" aria-label="Companion tabs">
            {SUB_TABS.map((tab) => {
              const isActive = activeTab === tab.id;
              const Icon = tab.icon;
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`
                    flex items-center gap-1.5 whitespace-nowrap pb-3 pt-2 px-1
                    text-sm font-medium border-b-2 transition-colors
                    ${isActive
                      ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                      : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300 hover:border-gray-300 dark:hover:border-gray-600'
                    }
                  `}
                >
                  <Icon className="h-4 w-4" />
                  <span className="hidden sm:inline">{tab.label}</span>
                  {/* Short label for mobile */}
                  <span className="sm:hidden">
                    {tab.id === 'trigger' ? 'Order?' : tab.label}
                  </span>
                </button>
              );
            })}
          </nav>
        </div>
      </div>

      {/* Tab content — scrollable */}
      <div className="flex-1 overflow-y-auto px-4 sm:px-6 py-4">
        {activeTab === 'suggestions' && <SuggestionBoard />}
        {activeTab === 'rules' && <RulesPanel />}
        {activeTab === 'trigger' && <ManualTriggerPanel />}
      </div>
    </div>
  );
}
