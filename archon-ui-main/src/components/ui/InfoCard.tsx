import React from 'react';
import { LucideIcon } from 'lucide-react';

interface InfoCardProps {
  title: string;
  description?: string;
  icon?: LucideIcon;
  value?: string | number;
  trend?: 'up' | 'down' | 'neutral';
  className?: string;
}

export const InfoCard: React.FC<InfoCardProps> = ({
  title,
  description,
  icon: Icon,
  value,
  trend,
  className = ''
}) => {
  const trendColors = {
    up: 'text-green-500',
    down: 'text-red-500',
    neutral: 'text-gray-500'
  };

  return (
    <div className={`
      bg-white dark:bg-black
      border border-gray-200 dark:border-gray-800
      rounded-lg p-6
      transition-all duration-300
      hover:shadow-md
      hover:border-green-500/30
      ${className}
    `}>
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <div className="flex items-center gap-3 mb-2">
            {Icon && (
              <div className="p-2 bg-green-500/10 rounded-lg">
                <Icon className="w-5 h-5 text-green-500" />
              </div>
            )}
            <h3 className="text-sm font-medium text-gray-600 dark:text-gray-400">
              {title}
            </h3>
          </div>
          
          {value !== undefined && (
            <div className="flex items-baseline gap-2">
              <span className="text-2xl font-semibold text-gray-900 dark:text-white">
                {value}
              </span>
              {trend && (
                <span className={`text-sm font-medium ${trendColors[trend]}`}>
                  {trend === 'up' ? '↑' : trend === 'down' ? '↓' : '→'}
                </span>
              )}
            </div>
          )}
          
          {description && (
            <p className="mt-2 text-sm text-gray-500 dark:text-gray-400">
              {description}
            </p>
          )}
        </div>
      </div>
    </div>
  );
};