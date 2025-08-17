import React from 'react';
import { Workflow, Navigation } from 'lucide-react';
import { SectionProps } from '../types/prp.types';
import { formatKey } from '../utils/formatters';

/**
 * Renders user flows and journey diagrams
 */
export const FlowSection: React.FC<SectionProps> = ({
  title,
  data,
  icon,
  accentColor = 'orange',
  defaultOpen = true,
  isDarkMode = false,
}) => {
  if (!data || typeof data !== 'object') return null;
  
  const renderFlowNode = (obj: any, depth: number = 0): React.ReactNode => {
    if (!obj || typeof obj !== 'object') {
      return <span className="text-gray-600 dark:text-gray-400">{String(obj)}</span>;
    }
    
    return Object.entries(obj).map(([key, value]) => {
      const nodeKey = `${key}-${depth}-${Math.random()}`;
      
      if (typeof value === 'string') {
        return (
          <div key={nodeKey} className="flex items-center gap-2 p-2" style={{ marginLeft: depth * 24 }}>
            <div className="w-2 h-2 rounded-full bg-green-500"></div>
            <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
              {formatKey(key)}:
            </span>
            <span className="text-sm text-gray-600 dark:text-gray-400">{value}</span>
          </div>
        );
      } else if (typeof value === 'object' && value !== null) {
        return (
          <div key={nodeKey} className="mb-3">
            <div className="flex items-center gap-2 p-2 font-medium text-gray-800 dark:text-white" style={{ marginLeft: depth * 24 }}>
              <Navigation className="w-4 h-4 text-green-500" />
              {formatKey(key)}
            </div>
            <div className="border-l-2 border-green-200 dark:border-green-800 ml-6">
              {renderFlowNode(value, depth + 1)}
            </div>
          </div>
        );
      }
      return null;
    });
  };
  
  return (
    <div className="grid gap-4">
      {Object.entries(data).map(([flowName, flow]) => (
        <div 
          key={flowName}
          className="p-4 rounded-lg bg-gradient-to-br from-green-50/50 to-green-50/50 dark:from-green-900/20 dark:to-green-900/20 border border-green-200 dark:border-green-800"
        >
          <h4 className="font-semibold text-gray-800 dark:text-white mb-3 flex items-center gap-2">
            <Workflow className="w-5 h-5 text-green-500" />
            {formatKey(flowName)}
          </h4>
          <div className="overflow-x-auto">
            {renderFlowNode(flow)}
          </div>
        </div>
      ))}
    </div>
  );
};