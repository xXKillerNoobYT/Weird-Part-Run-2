/**
 * QuickActions — dashboard buttons that launch the movement wizard
 * with pre-filled from/to locations.
 *
 * Each button opens the wizard with specific presets to streamline
 * the most common daily operations.
 */

import {
  ArrowDownToLine, Truck, RotateCcw, Plus,
} from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { Card, CardHeader } from '../../../../components/ui/Card';
import { useMovementWizardStore } from '../../stores/movement-wizard-store';

export function QuickActions() {
  const { open } = useMovementWizardStore();

  const actions = [
    {
      label: 'Pull to Staging',
      icon: <ArrowDownToLine className="h-4 w-4" />,
      onClick: () => open({
        fromLocationType: 'warehouse',
        toLocationType: 'pulled',
      }),
    },
    {
      label: 'Load Truck',
      icon: <Truck className="h-4 w-4" />,
      onClick: () => open({
        fromLocationType: 'pulled',
        toLocationType: 'truck',
      }),
    },
    {
      label: 'Return to Shelf',
      icon: <RotateCcw className="h-4 w-4" />,
      onClick: () => open({
        fromLocationType: 'truck',
        toLocationType: 'warehouse',
      }),
    },
    {
      label: 'New Movement',
      icon: <Plus className="h-4 w-4" />,
      onClick: () => open(),
    },
  ];

  return (
    <Card>
      <CardHeader title="Quick Actions" />
      <div className="grid grid-cols-2 gap-3">
        {actions.map((action) => (
          <Button
            key={action.label}
            variant="secondary"
            icon={action.icon}
            onClick={action.onClick}
            className="justify-start"
          >
            {action.label}
          </Button>
        ))}
      </div>
    </Card>
  );
}
