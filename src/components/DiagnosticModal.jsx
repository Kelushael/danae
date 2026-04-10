import { Shield, AlertCircle } from 'lucide-react';

export default function DiagnosticModal({ onDismiss }) {
  return (
    <>
      <div className="absolute inset-0 bg-black/85 backdrop-blur-sm z-[90]" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-[#0a0a0a] border-2 border-[#ff8c00] p-8 rounded-2xl shadow-[0_0_60px_rgba(255,140,0,0.35)] z-[100] max-w-md w-full text-center fade-up">
        <div className="flex justify-center mb-5">
          <div className="relative flex items-center justify-center w-16 h-16">
            <Shield size={64} className="text-[#ff8c00] opacity-15 absolute animate-ping" />
            <Shield size={64} className="text-[#ff8c00]" />
          </div>
        </div>

        <h2 className="text-white font-black text-lg mb-1 tracking-[0.2em] uppercase">
          M.O.M.-CORE // DIAGNOSTIC
        </h2>
        <p className="text-[#ff8c00] text-[9px] tracking-widest uppercase mb-5">
          Amira Learning · Sales Operations Intelligence
        </p>

        <div className="bg-[#111] border border-[#2a2a2a] p-4 rounded-lg mb-3 text-left">
          <p className="text-[#00ffc8] text-xs font-mono leading-relaxed">
            ✅ Local AI: <span className="text-white">qwen2.5-coder running</span><br/>
            ✅ Mode: <span className="text-white">Spatial Canvas — click anywhere</span><br/>
            ✅ Mission: <span className="text-white">CRM hygiene · renewals · orders</span>
          </p>
        </div>

        <div className="bg-[#0f0f0f] border border-[#1a1a1a] p-3 rounded-lg mb-6">
          <p className="text-gray-400 text-[10px] font-mono leading-relaxed italic">
            "Marcus put this here so you know everything is working, Denay.
            If something looks weird — it's not broken. Click Diagnostic anytime."
          </p>
        </div>

        <button
          onClick={onDismiss}
          className="px-8 py-3 bg-gradient-to-r from-[#ff8c00] to-red-600 text-black font-black uppercase tracking-widest rounded-lg hover:scale-105 active:scale-95 transition-all text-sm w-full"
        >
          Got It — Let's Work
        </button>
      </div>
    </>
  );
}
