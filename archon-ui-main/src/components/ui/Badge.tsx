import React from 'react';
interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  children: React.ReactNode;
  color?: 'green' | 'green' | 'gray' | 'orange';
  variant?: 'solid' | 'outline';
}
export const Badge: React.FC<BadgeProps> = ({
  children,
  color = 'gray',
  variant = 'outline',
  className = '',
  ...props
}) => {
  const colorMap = {
    solid: {
      green: 'bg-green-500/10 text-green-500 dark:bg-green-500/10 dark:text-green-500',
      green: 'bg-emerald-500/10 text-emerald-500 dark:bg-emerald-500/10 dark:text-emerald-500',
      green: 'bg-green-500/10 text-green-500 dark:bg-green-500/10 dark:text-green-500',
      blue: 'bg-green-500/10 text-green-500 dark:bg-green-500/10 dark:text-green-500',
      gray: 'bg-gray-200 text-gray-700 dark:bg-zinc-500/10 dark:text-zinc-400',
      orange: 'bg-orange-500/10 text-orange-500 dark:bg-orange-500/10 dark:text-orange-500'
    },
    outline: {
      green: 'border border-green-300 text-green-600 dark:border-green-500/30 dark:text-green-500',
      green: 'border border-emerald-300 text-emerald-600 dark:border-emerald-500/30 dark:text-emerald-500',
      green: 'border border-green-300 text-green-600 dark:border-green-500/30 dark:text-green-500',
      blue: 'border border-green-300 text-green-600 dark:border-green-500/30 dark:text-green-500',
      gray: 'border border-gray-300 text-gray-700 dark:border-zinc-700 dark:text-zinc-400',
      orange: 'border border-orange-500 text-orange-500 dark:border-orange-500 dark:text-orange-500 shadow-[0_0_10px_rgba(251,146,60,0.3)]'
    }
  };
  return <span className={`
        inline-flex items-center text-xs px-2 py-1 rounded
        ${colorMap[variant][color]}
        ${className}
      `} {...props}>
      {children}
    </span>;
};