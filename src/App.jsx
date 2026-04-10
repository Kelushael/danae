import { useState, useEffect, useCallback } from 'react';
import {
  Settings, AlertCircle, LayoutTemplate, X,
  MousePointerClick, Upload
} from 'lucide-react';
import { useOllama } from './hooks/useOllama';
import { TEMPLATES, MODE_PROMPTS, detectMode } from './lib/istation';
import DiagnosticModal from './components/DiagnosticModal';
import ConnectionHub from './components/ConnectionHub';
import PromptDialog from './components/PromptDialog';
import Widget from './components/Widget';

export default function App() {
  const [widgets, setWidgets] = useState([]);
  const [prompt, setPrompt] = useState(null);       // {x, y} or null
  const [ripples, setRipples] = useState([]);
  const [showHub, setShowHub] = useState(true);
  const [showTemplates, setShowTemplates] = useState(false);
  const [showDiag, setShowDiag] = useState(true);
  const [status, setStatus] = useState('Booting...');
  const { isConnected, checkConnection, generate, model } = useOllama();

  // Check Ollama on mount + every 30s
  useEffect(() => {
    checkConnection().then(ok => setStatus(ok ? 'Local AI live. Click anywhere.' : 'Ollama offline — start it or use cloud.'));
    const t = setInterval(checkConnection, 30000);
    return () => clearInterval(t);
  }, [checkConnection]);

  // Periodic diagnostic for mom — every 10 min
  useEffect(() => {
    const t = setInterval(() => setShowDiag(true), 600000);
    return () => clearInterval(t);
  }, []);

  // Canvas click → ripple + prompt
  const handleCanvas = useCallback((e) => {
    if (e.target.closest('.no-click')) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    // Ripple
    const id = Date.now();
    setRipples(r => [...r, { id, x, y }]);
    setTimeout(() => setRipples(r => r.filter(v => v.id !== id)), 1000);

    setPrompt({ x, y });
    setStatus(`Awaiting input at [${Math.round(x)}, ${Math.round(y)}]...`);
  }, []);

  // CSV upload handler
  const handleCSV = useCallback(async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const text = await file.text();
    const rows = text.split('\n').length;
    const x = window.innerWidth / 2;
    const y = window.innerHeight / 2;
    const id = Date.now();
    const intent = `Analyze uploaded CSV: ${file.name} (${rows} rows)`;

    setWidgets(w => [...w, { id, x, y, intent, mode: 'csv', status: 'building', output: '' }]);
    setStatus(`Feeding ${file.name} to AI...`);

    const csvPrompt = `${MODE_PROMPTS.csv}\n\nHere is the raw CSV data (first 8000 chars):\n\`\`\`\n${text.slice(0, 8000)}\n\`\`\``;
    try {
      await generate(csvPrompt, (token) => {
        setWidgets(w => w.map(v => v.id === id ? { ...v, output: v.output + token } : v));
      });
      setWidgets(w => w.map(v => v.id === id ? { ...v, status: 'done', title: `CSV: ${file.name}` } : v));
      setStatus('Analysis complete.');
    } catch (err) {
      setWidgets(w => w.map(v => v.id === id ? { ...v, status: 'done', title: 'Error', output: String(err) } : v));
    }
  }, [generate]);

  // Submit prompt → generate
  const handleSubmit = useCallback(async (fullPrompt, shortIntent, mode) => {
    const { x, y } = prompt;
    setPrompt(null);
    const id = Date.now();

    setWidgets(w => [...w, { id, x, y, intent: shortIntent, mode, status: 'building', output: '' }]);
    setStatus(`Routing "${shortIntent.slice(0, 30)}..." to ${model}...`);

    try {
      await generate(fullPrompt, (token) => {
        setWidgets(w => w.map(v => v.id === id ? { ...v, output: v.output + token } : v));
      });
      const modeTitle = { hygiene: 'CRM Hygiene', renewal: 'Renewal Scan', stuck: 'Stuck Deals', order: 'Order Check', summary: 'Exec Brief', csv: 'CSV Analysis', cost: 'AI Spend Analysis', adoption: 'Adoption Check-in', general: 'Analysis' };
      setWidgets(w => w.map(v => v.id === id ? { ...v, status: 'done', title: modeTitle[mode] || 'Result' } : v));
      setStatus('Ready. Click anywhere.');
    } catch (err) {
      setWidgets(w => w.map(v => v.id === id ? { ...v, status: 'done', title: 'Error', output: String(err) } : v));
      setStatus('Error — check Ollama.');
    }
  }, [prompt, generate, model]);

  // Template click → instant prompt
  const handleTemplate = useCallback((tmpl) => {
    setShowTemplates(false);
    const x = window.innerWidth / 2;
    const y = 200 + Math.random() * 200;
    const id = Date.now();

    setWidgets(w => [...w, { id, x, y, intent: tmpl.label, mode: tmpl.id, status: 'building', output: '' }]);
    setStatus(`Running ${tmpl.label}...`);

    generate(MODE_PROMPTS[tmpl.id], (token) => {
      setWidgets(w => w.map(v => v.id === id ? { ...v, output: v.output + token } : v));
    }).then(() => {
      setWidgets(w => w.map(v => v.id === id ? { ...v, status: 'done', title: tmpl.label } : v));
      setStatus('Ready.');
    }).catch(err => {
      setWidgets(w => w.map(v => v.id === id ? { ...v, status: 'done', title: 'Error', output: String(err) } : v));
    });
  }, [generate]);

  const removeWidget = useCallback((id) => {
    setWidgets(w => w.filter(v => v.id !== id));
  }, []);

  return (
    <div className="h-screen w-screen bg-[#020202] text-[#00ffc8] font-mono flex flex-col overflow-hidden relative">

      {/* Diagnostic overlay */}
      {showDiag && <DiagnosticModal onDismiss={() => setShowDiag(false)} />}

      {/* Header */}
      <header className="no-click relative z-50 flex justify-between items-center p-3 bg-[#050505] border-b border-[#1a1a1a]">
        <div className="flex items-center gap-3 pl-2">
          <button onClick={() => setShowHub(!showHub)} className="p-1.5 hover:bg-[#222] rounded transition-colors">
            <Settings size={15} className="text-[#ff8c00]" />
          </button>
          <div>
            <h1 className="text-[10px] font-black tracking-[0.3em] text-white uppercase opacity-80">
              M.O.M.-CORE // ISTATION SALESOPS
            </h1>
            <span className="text-[8px] text-teal-500 uppercase tracking-widest">{status}</span>
          </div>
        </div>

        <div className="flex items-center gap-3 pr-2">
          {/* CSV Upload */}
          <label className="flex items-center gap-2 px-3 py-1 rounded border border-teal-500/30 hover:bg-teal-500/10 text-teal-400 text-[9px] uppercase tracking-widest font-bold transition-all cursor-pointer">
            <Upload size={11} />
            Upload CSV
            <input type="file" accept=".csv" className="hidden" onChange={handleCSV} />
          </label>

          <button onClick={() => setShowDiag(true)}
            className="flex items-center gap-2 px-3 py-1 rounded border border-[#ff8c00]/30 hover:bg-[#ff8c00]/10 text-[#ff8c00] text-[9px] uppercase tracking-widest font-bold transition-all">
            <AlertCircle size={11} /> Diagnostic
          </button>

          <button onClick={() => setShowTemplates(!showTemplates)}
            className="flex items-center gap-2 px-4 py-1.5 rounded-full border border-[#333] hover:border-teal-500 hover:bg-teal-500/10 transition-all text-[9px] uppercase tracking-widest font-bold text-white">
            <LayoutTemplate size={11} /> Templates
          </button>
        </div>
      </header>

      {/* Connection Hub */}
      {showHub && <div className="no-click"><ConnectionHub isConnected={isConnected} model={model} /></div>}

      {/* Template Drawer */}
      {showTemplates && (
        <div className="no-click absolute top-14 right-4 w-72 bg-[#0a0a0a] border border-[#333] rounded-xl p-4 z-50 shadow-2xl fade-up">
          <div className="flex justify-between items-center mb-4 pb-2 border-b border-[#222]">
            <span className="text-[9px] uppercase tracking-widest text-[#ff8c00] font-bold">Istation SalesOps Templates</span>
            <button onClick={() => setShowTemplates(false)}><X size={13} className="text-gray-600 hover:text-white" /></button>
          </div>
          <div className="space-y-2">
            {TEMPLATES.map(t => (
              <button key={t.id} onClick={() => handleTemplate(t)}
                className="w-full p-3 text-left border border-[#222] hover:border-[#00ffc8] rounded-lg text-[10px] transition-colors group">
                <span className="mr-2">{t.icon}</span>
                <span className="text-white font-bold">{t.label}</span>
                <p className="text-gray-500 text-[9px] mt-1 ml-5">{t.desc}</p>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Canvas */}
      <div className="flex-1 relative cursor-crosshair overflow-hidden" onClick={handleCanvas}
        style={{
          backgroundImage: 'linear-gradient(rgba(26,26,26,0.4) 1px, transparent 1px), linear-gradient(90deg, rgba(26,26,26,0.4) 1px, transparent 1px)',
          backgroundSize: '40px 40px',
        }}>

        {/* Empty state */}
        {widgets.length === 0 && !prompt && (
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none opacity-20">
            <div className="flex flex-col items-center gap-4">
              <MousePointerClick size={48} className="animate-bounce" />
              <p className="text-sm tracking-[0.4em] uppercase font-black text-center">
                Canvas Empty<br/>
                <span className="text-[10px] text-[#ff8c00] tracking-widest">Click anywhere · Upload CSV · Use a template</span>
              </p>
            </div>
          </div>
        )}

        {/* Ripples */}
        {ripples.map(r => (
          <div key={r.id} className="absolute rounded-full border border-[#00ffc8] pointer-events-none"
            style={{ left: r.x, top: r.y, width: 0, height: 0, transform: 'translate(-50%,-50%)', animation: 'ripple 1s cubic-bezier(0.1,0.8,0.3,1) forwards' }} />
        ))}

        {/* Widgets */}
        {widgets.map(w => (
          <Widget key={w.id} widget={w} onRemove={removeWidget} />
        ))}

        {/* Prompt */}
        {prompt && (
          <PromptDialog x={prompt.x} y={prompt.y} onSubmit={handleSubmit} onClose={() => setPrompt(null)} />
        )}
      </div>
    </div>
  );
}
