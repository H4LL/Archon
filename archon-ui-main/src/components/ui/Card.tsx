import React from 'react';

interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  children: React.ReactNode;
  variant?: 'default' | 'bordered' | 'elevated';
  hover?: boolean;
}

export const Card: React.FC<CardProps> = ({
  children,
  variant = 'default',
  hover = true,
  className = '',
  ...props
}) => {
  const variantClasses = {
    default: `
      bg-white dark:bg-black
      border border-gray-200 dark:border-gray-800
      shadow-sm
    `,
    bordered: `
      bg-white dark:bg-black
      border-2 border-green-500/20
      shadow-sm
    `,
    elevated: `
      bg-gradient-to-b from-white to-gray-50 dark:from-gray-900 dark:to-black
      border border-gray-200 dark:border-gray-800
      shadow-md
    `
  };

  const hoverClasses = hover ? `
    transition-all duration-300
    hover:shadow-lg
    hover:border-green-500/30
    hover:-translate-y-0.5
  ` : '';

  return (
    <div
      className={`
        rounded-lg p-6
        ${variantClasses[variant]}
        ${hoverClasses}
        ${className}
      `}
      {...props}
    >
      {children}
    </div>
  );
};