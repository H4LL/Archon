import React from 'react';
interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  accentColor?: 'green' | 'green';
  icon?: React.ReactNode;
  label?: string;
}
export const Input: React.FC<InputProps> = ({
  accentColor = 'green',
  icon,
  label,
  className = '',
  ...props
}) => {
  const accentColorMap = {
    green: 'focus-within:border-green-500 focus-within:shadow-[0_0_15px_rgba(168,85,247,0.5)]',
    green: 'focus-within:border-emerald-500 focus-within:shadow-[0_0_15px_rgba(16,185,129,0.5)]',
    green: 'focus-within:border-green-500 focus-within:shadow-[0_0_15px_rgba(80,200,120,0.5)]',
    blue: 'focus-within:border-green-500 focus-within:shadow-[0_0_15px_rgba(59,130,246,0.5)]'
  };
  return <div className="w-full">
      {label && <label className="block text-gray-600 dark:text-zinc-400 text-sm mb-1.5">
          {label}
        </label>}
      <div className={`
        flex items-center bg-white dark:bg-black bg-gradient-to-b dark:from-white/10 dark:to-black/30 from-white/80 to-white/60 
        border dark:border-gray-200 dark:border-gray-800 border-gray-200 rounded-md px-3 py-2
        transition-all duration-200 ${accentColorMap[accentColor]}
      `}>
        {icon && <div className="mr-2 text-gray-500 dark:text-zinc-500">{icon}</div>}
        <input className={`
            w-full bg-transparent text-gray-800 dark:text-white placeholder:text-gray-400 dark:placeholder:text-zinc-600
            focus:outline-none ${className}
          `} {...props} />
      </div>
    </div>;
};