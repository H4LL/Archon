import React from 'react';
import { Hash } from 'lucide-react';
import { PRPSectionProps } from '../types/prp.types';
import { formatKey, formatValue } from '../utils/formatters';

/**
 * Component for rendering simple key-value pairs
 * Used for sections like budget, resources, team, etc.
 */
export const KeyValueSection: React.FC<PRPSectionProps> = ({ 
  title, 
  data, 
  icon = <Hash className="w-5 h-5" />,
  accentColor = 'green',
  isDarkMode = false,
  defaultOpen = true 
}) => {
  if (!data || typeof data !== 'object') return null;

  const colorMap = {
    blue: 'from-green-400 to-green-600',
    green: 'from-green-400 to-green-600',
    green: 'from-green-400 to-green-600',
    orange: 'from-orange-400 to-orange-600',
    green: 'from-green-400 to-green-600',
    cyan: 'from-green-400 to-green-600',
    indigo: 'from-green-400 to-green-600',
    emerald: 'from-emerald-400 to-emerald-600',
  };

  const borderColorMap = {
    blue: 'border-green-200 dark:border-green-800',
    green: 'border-green-200 dark:border-green-800',
    green: 'border-green-200 dark:border-green-800',
    orange: 'border-orange-200 dark:border-orange-800',
    green: 'border-green-200 dark:border-green-800',
    cyan: 'border-green-200 dark:border-green-800',
    indigo: 'border-green-200 dark:border-green-800',
    emerald: 'border-emerald-200 dark:border-emerald-800',
  };

  const renderValue = (value: any): React.ReactNode => {
    if (Array.isArray(value)) {
      return (
        <ul className="list-disc list-inside space-y-1 mt-1">
          {value.map((item, index) => (
            <li key={index} className="text-gray-600 dark:text-gray-400">
              {formatValue(item)}
            </li>
          ))}
        </ul>
      );
    }
    
    if (typeof value === 'object' && value !== null) {
      return (
        <div className="mt-2 space-y-2 bg-gray-50 dark:bg-gray-700 p-3 rounded">
          {Object.entries(value).map(([k, v]) => (
            <div key={k} className="flex items-center justify-between">
              <span className="font-medium text-gray-600 dark:text-gray-400">
                {formatKey(k)}
              </span>
              <span className="text-gray-700 dark:text-gray-300 font-semibold">
                {formatValue(v)}
              </span>
            </div>
          ))}
        </div>
      );
    }
    
    return (
      <span className="text-gray-700 dark:text-gray-300 font-semibold">
        {formatValue(value)}
      </span>
    );
  };

  return (
    <div className="space-y-4">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6 border border-gray-200 dark:border-gray-700">
        <div className="flex items-center gap-3 mb-6">
          <div className={`p-2 rounded-lg bg-gradient-to-br ${colorMap[accentColor as keyof typeof colorMap] || colorMap.green} text-white shadow-lg`}>
            {icon}
          </div>
          <h3 className="text-lg font-bold text-gray-800 dark:text-white">
            {title}
          </h3>
        </div>
        
        <div className="space-y-4">
          {Object.entries(data).map(([key, value]) => (
            <div 
              key={key} 
              className={`pb-4 border-b ${borderColorMap[accentColor as keyof typeof borderColorMap] || borderColorMap.green} last:border-0 last:pb-0`}
            >
              <div className="flex items-start justify-between gap-4">
                <h4 className="font-semibold text-gray-700 dark:text-gray-300 min-w-[120px]">
                  {formatKey(key)}
                </h4>
                <div className="flex-1 text-right">
                  {renderValue(value)}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};