import { Cpu, Database, Wifi, Circle } from 'lucide-react';

export default function ConnectionHub({ isConnected, model }) {
  const dot = isConnected === null
    ? 'text-yellow-500 animate-pulse'
    : isConnected ? 'text-[#00ffc8]' : 'text-red-500';

  const label = isConnected === null ? 'Checking...' : isConnected ? 'Live' : 'Offline';

  return (
    <div className="absolute top-14 left-3 bg-black/90 border border-[#1e1e1e] p-3 rounded-xl z-40 w-64 shadow-2xl backdrop-blur-md">
      <h3 className="text-[#00ffc8] text-[9px] font-black uppercase mb-3 flex items-center gap-2 tracking-widest">
        <Wifi size={10} /> LLM Connection
      </h3>
      <div className="space-y-1.5 text-[9px] font-mono">
        <div className="flex justify-between items-center p-2 border border-[#00ffc8]/40 rounded bg-[#00ffc8]/5 text-white">
          <span className="flex items-center gap-2">
            <Cpu size={10} className="text-[#00ffc8]" /> Ollama · {model}
          </span>
          <span className={`flex items-center gap-1 ${dot}`}>
            <Circle size={6} fill="currentColor" /> {label}
          </span>
        </div>
        <div className="flex justify-between items-center p-2 border border-[#222] rounded text-gray-600">
          <span className="flex items-center gap-2"><Database size={10} /> LM Studio</span>
          <span>Standby</span>
        </div>
        <div className="flex justify-between items-center p-2 border border-[#222] rounded text-gray-600">
          <span className="flex items-center gap-2">
            <svg width={10} height={10} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"/></svg>
            OpenRouter
          </span>
          <span>Standby</span>
        </div>
      </div>
    </div>
  );
}
