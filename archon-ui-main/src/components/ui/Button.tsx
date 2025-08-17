import React from 'react';

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  children: React.ReactNode;
  variant?: 'primary' | 'secondary' | 'outline' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
  icon?: React.ReactNode;
}

export const Button: React.FC<ButtonProps> = ({
  children,
  variant = 'primary',
  size = 'md',
  icon,
  className = '',
  ...props
}) => {
  const sizeClasses = {
    sm: 'text-xs px-4 py-2',
    md: 'text-sm px-7 py-3',
    lg: 'text-base px-8 py-4'
  };

  const variantClasses = {
    primary: `
      bg-gradient-to-r from-green-500 to-green-600
      text-white font-medium
      rounded-lg
      transition-all duration-300
      hover:opacity-80
      active:scale-[0.98]
    `,
    secondary: `
      bg-black/90
      text-white font-medium
      border border-green-500/30
      rounded-lg
      transition-all duration-300
      hover:bg-green-500/10
      hover:border-green-500/50
      active:scale-[0.98]
    `,
    outline: `
      bg-transparent
      text-green-500 font-medium
      border border-green-500
      rounded-lg
      transition-all duration-300
      hover:bg-green-500/10
      hover:text-green-400
      active:scale-[0.98]
    `,
    ghost: `
      bg-transparent
      text-gray-300 font-medium
      rounded-lg
      transition-all duration-300
      hover:bg-white/5
      hover:text-white
      active:scale-[0.98]
    `
  };

  return (
    <button
      className={`
        inline-flex items-center justify-center
        ${variantClasses[variant]}
        ${sizeClasses[size]}
        ${className}
      `}
      {...props}
    >
      {icon && <span className="mr-2">{icon}</span>}
      {children}
    </button>
  );
};