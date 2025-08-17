import React from 'react';
import { motion } from 'framer-motion';

interface PowerButtonProps {
  isOn: boolean;
  onClick: () => void;
  size?: number;
}

export const PowerButton: React.FC<PowerButtonProps> = ({
  isOn,
  onClick,
  size = 40
}) => {
  return (
    <motion.button
      onClick={onClick}
      className={`
        relative rounded-full border-2 transition-all duration-300
        ${isOn 
          ? 'border-green-500 bg-gradient-to-b from-green-500/20 to-green-600/20' 
          : 'border-gray-600 bg-white dark:bg-black'
        }
        hover:scale-105
        active:scale-95
      `}
      style={{ width: size, height: size }}
      whileHover={{ scale: 1.05 }}
      whileTap={{ scale: 0.95 }}
    >
      {/* Subtle glow when on */}
      {isOn && (
        <motion.div
          className="absolute inset-0 rounded-full bg-green-500/30"
          animate={{
            opacity: [0.3, 0.5, 0.3],
          }}
          transition={{
            duration: 2,
            repeat: Infinity,
            ease: "easeInOut"
          }}
        />
      )}

      {/* Power symbol */}
      <svg
        width={size * 0.5}
        height={size * 0.5}
        viewBox="0 0 24 24"
        fill="none"
        className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2"
      >
        <path
          d="M12 2L12 12"
          stroke={isOn ? '#50c878' : '#6b7280'}
          strokeWidth="2.5"
          strokeLinecap="round"
        />
        <path
          d="M18.36 6.64a9 9 0 1 1-12.73 0"
          stroke={isOn ? '#50c878' : '#6b7280'}
          strokeWidth="2.5"
          strokeLinecap="round"
        />
      </svg>
    </motion.button>
  );
};