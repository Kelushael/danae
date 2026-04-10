import { useState, useCallback, useRef } from 'react';
import { SYSTEM_PROMPT } from '../lib/istation';

const BASE_URL = 'http://localhost:11434';
const MODEL = 'qwen2.5-coder:1.5b';

export function useOllama() {
  const [isConnected, setIsConnected] = useState(null);
  const abortRef = useRef(null);

  const checkConnection = useCallback(async () => {
    try {
      const r = await fetch(`${BASE_URL}/api/tags`, { signal: AbortSignal.timeout(3000) });
      setIsConnected(r.ok);
      return r.ok;
    } catch {
      setIsConnected(false);
      return false;
    }
  }, []);

  const generate = useCallback(async (userPrompt, onChunk) => {
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    const res = await fetch(`${BASE_URL}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: MODEL,
        stream: true,
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user',   content: userPrompt },
        ],
      }),
      signal: controller.signal,
    });

    if (!res.ok) throw new Error(`Ollama ${res.status}: ${await res.text()}`);

    const reader = res.body.getReader();
    const dec = new TextDecoder();
    let full = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const lines = dec.decode(value).split('\n').filter(Boolean);
      for (const line of lines) {
        try {
          const token = JSON.parse(line).message?.content ?? '';
          if (token) { full += token; onChunk(token); }
        } catch { /* partial */ }
      }
    }
    return full;
  }, []);

  const cancel = useCallback(() => abortRef.current?.abort(), []);

  return { isConnected, checkConnection, generate, cancel, model: MODEL };
}
