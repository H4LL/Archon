import React from 'react';
interface SelectProps extends React.SelectHTMLAttributes<HTMLSelectElement> {
  accentColor?: 'green' | 'green';
  label?: string;
  options: {
    value: string;
    label: string;
  }[];
}
export const Select: React.FC<SelectProps> = ({
  accentColor = 'green',
  label,
  options,
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
        relative bg-white dark:bg-black bg-gradient-to-b dark:from-white/10 dark:to-black/30 from-white/80 to-white/60
        border dark:border-gray-200 dark:border-gray-800 border-gray-200 rounded-md
        transition-all duration-200 ${accentColorMap[accentColor]}
      `}>
        <select className={`
            w-full bg-transparent text-gray-800 dark:text-white appearance-none px-3 py-2
            focus:outline-none ${className}
          `} {...props}>
          {options.map(option => <option key={option.value} value={option.value} className="bg-white dark:bg-zinc-900">
              {option.label}
            </option>)}
        </select>
        <div className="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none text-gray-500 dark:text-zinc-500">
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M2.5 4.5L6 8L9.5 4.5" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
      </div>
    </div>;
};