import { useState, useRef } from 'react';
import { Database, X, Check, Cpu, Square } from 'lucide-react';

export default function Widget({ widget, onRemove }) {
  const { id, title, intent, status, output, mode } = widget;
  const isBuilding = status === 'building';

  const modeColors = {
    hygiene: 'border-yellow-500/40 hover:border-yellow-500',
    renewal: 'border-blue-500/40 hover:border-blue-500',
    stuck:   'border-red-500/40 hover:border-red-500',
    order:   'border-purple-500/40 hover:border-purple-500',
    summary: 'border-[#ff8c00]/40 hover:border-[#ff8c00]',
    general: 'border-[#333] hover:border-[#00ffc8]',
  };

  const modeIcons = {
    hygiene: '🧹', renewal: '🔄', stuck: '🚨',
    order: '📋', summary: '📊', general: '🤖',
  };

  const borderClass = modeColors[mode] || modeColors.general;

  return (
    <div
      className={`absolute bg-[#080808] border shadow-2xl rounded-xl p-4 w-72 transition-all duration-300 group fade-up ${borderClass}`}
      style={{
        left: widget.x,
        top: widget.y,
        transform: isBuilding
          ? 'translate(-50%, -50%) scale(0.96)'
          : 'translate(-50%, -50%) scale(1)',
        opacity: isBuilding ? 0.85 : 1,
        maxHeight: '420px',
      }}
      onClick={e => e.stopPropagation()}
    >
      {/* Header */}
      <div className="flex justify-between items-start mb-3 pb-2 border-b border-[#1a1a1a]">
        <h3 className="text-[11px] font-black text-[#00ffc8] uppercase tracking-widest flex items-center gap-2">
          <span>{modeIcons[mode] ?? '🤖'}</span>
          {isBuilding ? 'Analyzing...' : title}
        </h3>
        <button
          onClick={() => onRemove(id)}
          className="opacity-0 group-hover:opacity-100 text-gray-700 hover:text-red-500 transition-all ml-2 shrink-0"
        >
          <X size={12} />
        </button>
      </div>

      {/* Intent badge */}
      <div className="text-[9px] text-gray-500 italic border-l-2 border-[#222] pl-2 mb-3 truncate">
        "{intent}"
      </div>

      {/* Content */}
      {isBuilding ? (
        <div className="space-y-2">
          <div className="flex items-center gap-2 text-[#ff8c00] text-[10px] font-bold uppercase tracking-widest animate-pulse">
            <Cpu size={11} /> Routing to local AI...
          </div>
          <div className="w-full h-0.5 bg-[#1a1a1a] rounded overflow-hidden">
            <div className="h-full bg-gradient-to-r from-[#ff8c00] to-[#00ffc8] w-2/3 animate-pulse" />
          </div>
        </div>
      ) : (
        <div
          className="text-[10px] text-gray-300 leading-relaxed font-mono overflow-y-auto"
          style={{ maxHeight: '280px', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}
        >
          {output}
        </div>
      )}
    </div>
  );
}
