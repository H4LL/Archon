import React from 'react';
import { Moon, Sun } from 'lucide-react';
import { useTheme } from '../../contexts/ThemeContext';
interface ThemeToggleProps {
  accentColor?: 'green' | 'green';
}
export const ThemeToggle: React.FC<ThemeToggleProps> = ({
  accentColor = 'green'
}) => {
  const {
    theme,
    setTheme
  } = useTheme();
  const toggleTheme = () => {
    setTheme(theme === 'dark' ? 'light' : 'dark');
  };
  const accentColorMap = {
    green: {
      border: 'border-green-300 dark:border-green-500/30',
      hover: 'hover:border-green-400 dark:hover:border-green-500/60',
      text: 'text-green-600 dark:text-green-500',
      bg: 'from-green-100/80 to-green-50/60 dark:from-white/10 dark:to-black/30'
    },
    green: {
      border: 'border-emerald-300 dark:border-emerald-500/30',
      hover: 'hover:border-emerald-400 dark:hover:border-emerald-500/60',
      text: 'text-emerald-600 dark:text-emerald-500',
      bg: 'from-emerald-100/80 to-emerald-50/60 dark:from-white/10 dark:to-black/30'
    },
    green: {
      border: 'border-green-300 dark:border-green-500/30',
      hover: 'hover:border-green-400 dark:hover:border-green-500/60',
      text: 'text-green-600 dark:text-green-500',
      bg: 'from-green-100/80 to-green-50/60 dark:from-white/10 dark:to-black/30'
    },
    blue: {
      border: 'border-green-300 dark:border-green-500/30',
      hover: 'hover:border-green-400 dark:hover:border-green-500/60',
      text: 'text-green-600 dark:text-green-500',
      bg: 'from-green-100/80 to-green-50/60 dark:from-white/10 dark:to-black/30'
    }
  };
  return <button onClick={toggleTheme} className={`
        relative p-2 rounded-md bg-white dark:bg-black 
        bg-gradient-to-b ${accentColorMap[accentColor].bg}
        border ${accentColorMap[accentColor].border} ${accentColorMap[accentColor].hover}
        ${accentColorMap[accentColor].text}
        shadow-[0_0_10px_rgba(0,0,0,0.05)] dark:shadow-[0_0_10px_rgba(0,0,0,0.3)]
        transition-all duration-300 flex items-center justify-center
      `} aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}>
      {theme === 'dark' ? <Sun className="w-5 h-5" /> : <Moon className="w-5 h-5" />}
    </button>;
};