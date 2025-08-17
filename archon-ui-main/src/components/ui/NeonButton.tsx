import React from 'react';
import { motion, HTMLMotionProps } from 'framer-motion';
import { cn } from '../../lib/utils';

export interface NeonButtonProps extends HTMLMotionProps<'button'> {
  children: React.ReactNode;
  variant?: 'primary' | 'secondary' | 'outline';
  size?: 'sm' | 'md' | 'lg';
  fullWidth?: boolean;
}

export const NeonButton = React.forwardRef<HTMLButtonElement, NeonButtonProps>(({
  children,
  variant = 'primary',
  size = 'md',
  fullWidth = false,
  className,
  disabled,
  ...props
}, ref) => {
  const sizeClasses = {
    sm: 'text-xs px-4 py-2',
    md: 'text-sm px-7 py-3',
    lg: 'text-base px-8 py-4'
  };

  const variantClasses = {
    primary: cn(
      'relative overflow-hidden',
      'bg-gradient-to-r from-green-500 to-green-600',
      'text-white font-medium',
      'rounded-lg',
      'transition-all duration-300',
      'hover:shadow-lg hover:shadow-green-500/25',
      'active:scale-[0.98]',
      'disabled:opacity-50 disabled:cursor-not-allowed',
      'before:absolute before:inset-0',
      'before:bg-gradient-to-r before:from-transparent before:via-white/20 before:to-transparent',
      'before:translate-x-[-200%]',
      'hover:before:translate-x-[200%]',
      'before:transition-transform before:duration-700'
    ),
    secondary: cn(
      'bg-black/90',
      'text-white font-medium',
      'border border-green-500/30',
      'rounded-lg',
      'transition-all duration-300',
      'hover:bg-green-500/10',
      'hover:border-green-500/50',
      'hover:shadow-lg hover:shadow-green-500/20',
      'active:scale-[0.98]',
      'disabled:opacity-50 disabled:cursor-not-allowed'
    ),
    outline: cn(
      'bg-transparent',
      'text-green-500 font-medium',
      'border border-green-500',
      'rounded-lg',
      'transition-all duration-300',
      'hover:bg-green-500/10',
      'hover:text-green-400',
      'hover:shadow-lg hover:shadow-green-500/20',
      'active:scale-[0.98]',
      'disabled:opacity-50 disabled:cursor-not-allowed'
    )
  };

  return (
    <motion.button
      ref={ref}
      className={cn(
        'inline-flex items-center justify-center',
        variantClasses[variant],
        sizeClasses[size],
        fullWidth && 'w-full',
        className
      )}
      disabled={disabled}
      whileHover={{ scale: disabled ? 1 : 1.02 }}
      whileTap={{ scale: disabled ? 1 : 0.98 }}
      {...props}
    >
      <span className="relative z-10">
        {children}
      </span>
    </motion.button>
  );
});

NeonButton.displayName = 'NeonButton';