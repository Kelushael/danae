import { useState, useRef, useCallback } from 'react';
import { Sparkles, Mic, X } from 'lucide-react';
import { detectMode, MODE_PROMPTS } from '../lib/istation';

export default function PromptDialog({ x, y, onSubmit, onClose }) {
  const [text, setText] = useState('');
  const inputRef = useRef(null);

  const submit = () => {
    const t = text.trim();
    if (!t) { onClose(); return; }
    const mode = detectMode(t);
    const fullPrompt = `${MODE_PROMPTS[mode]}\n\nUser context: ${t}`;
    onSubmit(fullPrompt, t, mode);
  };

  return (
    <div
      className="absolute bg-[#0d0d0d] border border-[#00ffc8]/60 shadow-[0_0_40px_rgba(0,255,200,0.15)] rounded-2xl p-5 w-80 fade-up z-50"
      style={{ left: x, top: y, transform: 'translate(-50%, -50%)' }}
      onClick={e => e.stopPropagation()}
    >
      <div className="flex justify-between items-center mb-3">
        <span className="flex items-center gap-2 text-[11px] font-bold text-white tracking-widest uppercase">
          <Sparkles size={13} className="text-[#00ffc8] animate-pulse" />
          What goes here?
        </span>
        <button onClick={onClose} className="text-gray-600 hover:text-white transition-colors">
          <X size={13} />
        </button>
      </div>

      <textarea
        ref={inputRef}
        autoFocus
        className="w-full bg-black/60 border border-[#2a2a2a] rounded-lg p-3 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-[#ff8c00] transition-colors resize-none h-20 font-mono"
        placeholder="e.g. check renewal pipeline... find stuck deals... CRM hygiene..."
        value={text}
        onChange={e => setText(e.target.value)}
        onKeyDown={e => {
          if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit(); }
          if (e.key === 'Escape') onClose();
        }}
      />

      <div className="flex justify-between items-center mt-3">
        <span className="text-[8px] text-gray-600 uppercase tracking-widest">Enter to run · Esc to cancel</span>
        <button
          onClick={submit}
          className="px-5 py-2 bg-gradient-to-r from-[#00ffc8] to-[#0088ff] text-black font-black text-[10px] uppercase tracking-widest rounded shadow-[0_0_15px_rgba(0,255,200,0.3)] hover:scale-105 active:scale-95 transition-all"
        >
          Run
        </button>
      </div>
    </div>
  );
}
