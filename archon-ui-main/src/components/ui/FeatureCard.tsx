import React from 'react';
import { LucideIcon } from 'lucide-react';
import { motion } from 'framer-motion';

interface FeatureCardProps {
  title: string;
  description: string;
  icon: LucideIcon;
  href?: string;
  onClick?: () => void;
  className?: string;
}

export const FeatureCard: React.FC<FeatureCardProps> = ({
  title,
  description,
  icon: Icon,
  href,
  onClick,
  className = ''
}) => {
  const CardWrapper = href ? 'a' : onClick ? 'button' : 'div';
  const isInteractive = href || onClick;

  return (
    <motion.div
      whileHover={isInteractive ? { scale: 1.02 } : {}}
      whileTap={isInteractive ? { scale: 0.98 } : {}}
      className="h-full"
    >
      <CardWrapper
        href={href}
        onClick={onClick}
        className={`
          block h-full
          bg-gradient-to-b from-white to-gray-50 dark:from-gray-900 dark:to-black
          border border-gray-200 dark:border-gray-800
          rounded-lg p-6
          transition-all duration-300
          ${isInteractive ? 'cursor-pointer hover:shadow-lg hover:border-green-500/30' : ''}
          ${className}
        `}
      >
        <div className="flex flex-col h-full">
          <div className="flex items-center gap-4 mb-4">
            <div className="p-3 bg-gradient-to-br from-green-500/10 to-green-600/10 rounded-lg">
              <Icon className="w-6 h-6 text-green-500" />
            </div>
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              {title}
            </h3>
          </div>
          
          <p className="text-sm text-gray-600 dark:text-gray-400 flex-1">
            {description}
          </p>
          
          {isInteractive && (
            <div className="mt-4 text-sm font-medium text-green-500">
              Learn more →
            </div>
          )}
        </div>
      </CardWrapper>
    </motion.div>
  );
};