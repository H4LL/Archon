import { User, Bot, Tag, Clipboard } from 'lucide-react';
import React from 'react';
import { XanaduLogo } from '../components/ui/XanaduLogo';

export const ItemTypes = {
  TASK: 'task'
};

export const getAssigneeIcon = (assigneeName: 'User' | 'Archon' | 'AI IDE Agent') => {
  switch (assigneeName) {
    case 'User':
      return <User className="w-4 h-4 text-green-400" />;
    case 'AI IDE Agent':
      return <Bot className="w-4 h-4 text-green-400" />;
    case 'Archon':
      return <XanaduLogo size="sm" className="text-green-500 dark:text-white" />;
    default:
      return <User className="w-4 h-4 text-green-400" />;
  }
};

export const getAssigneeGlow = (assigneeName: 'User' | 'Archon' | 'AI IDE Agent') => {
  switch (assigneeName) {
    case 'User':
      return 'shadow-[0_0_10px_rgba(#50c878,0.4)]';
    case 'AI IDE Agent':
      return 'shadow-[0_0_10px_rgba(#50c878,0.4)]';
    case 'Archon':
      return 'shadow-[0_0_10px_rgba(34,211,238,0.4)]';
    default:
      return 'shadow-[0_0_10px_rgba(#50c878,0.4)]';
  }
};

export const getOrderColor = (order: number) => {
  if (order <= 3) return 'bg-rose-500';
  if (order <= 6) return 'bg-orange-500';
  if (order <= 10) return 'bg-green-500';
  return 'bg-green-500';
};

export const getOrderGlow = (order: number) => {
  if (order <= 3) return 'shadow-[0_0_10px_rgba(244,63,94,0.7)]';
  if (order <= 6) return 'shadow-[0_0_10px_rgba(249,115,22,0.7)]';
  if (order <= 10) return 'shadow-[0_0_10px_rgba(#50c878,0.7)]';
  return 'shadow-[0_0_10px_rgba(#50c878,0.7)]';
}; 