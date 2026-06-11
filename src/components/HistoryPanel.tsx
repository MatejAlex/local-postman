'use client';

import type { HistoryItem } from '../lib/types';
import { formatTime, statusColor } from '../lib/utils';

interface Props {
  history: HistoryItem[];
  onReplay: (item: HistoryItem) => void;
  onClear: () => void;
}

export default function HistoryPanel({ history, onReplay, onClear }: Props) {
  return (
    <aside className="w-72 shrink-0 flex flex-col bg-[var(--bg-elev)] border-l border-[var(--border)] overflow-hidden">
      <div className="flex items-center justify-between px-3 py-2.5 border-b border-[var(--border)]">
        <span className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-fg)]">
          History
        </span>
        {history.length > 0 && (
          <button onClick={onClear} className="text-xs text-[var(--muted-fg)] hover:text-[var(--danger)]">
            Clear
          </button>
        )}
      </div>
      <div className="flex-1 overflow-auto">
        {history.length === 0 && (
          <p className="px-3 py-3 text-xs text-[var(--muted-fg)]">No requests sent yet.</p>
        )}
        {history.map((item) => (
          <button
            key={item.id}
            onClick={() => onReplay(item)}
            className="w-full text-left px-3 py-2 border-b border-[var(--border)] hover:bg-[var(--hover)]"
          >
            <div className="flex items-center gap-2">
              <span className={`text-[10px] font-bold w-10 shrink-0 method-${item.method}`}>
                {item.method}
              </span>
              {item.response.error ? (
                <span className="text-xs font-semibold text-[var(--danger)]">ERR</span>
              ) : (
                <span
                  className="text-xs font-semibold"
                  style={{ color: statusColor(item.response.status) }}
                >
                  {item.response.status}
                </span>
              )}
              <span className="ml-auto text-[10px] text-[var(--muted-fg)]">
                {formatTime(item.response.timeMs)}
              </span>
            </div>
            <div className="mt-0.5 text-xs text-[var(--muted-fg)] truncate font-mono">{item.url}</div>
          </button>
        ))}
      </div>
    </aside>
  );
}
