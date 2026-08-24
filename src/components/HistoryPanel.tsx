'use client';

import type { HistoryItem } from '../lib/types';
import { formatTime, statusColor } from '../lib/utils';

interface Props {
  history: HistoryItem[];
  onInspect: (item: HistoryItem) => void;
  onReplay: (item: HistoryItem) => void;
  onClear: () => void;
}

export default function HistoryPanel({ history, onInspect, onReplay, onClear }: Props) {
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
          <div
            key={item.id}
            className="px-3 py-2 border-b border-[var(--border)] hover:bg-[var(--hover)] group"
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
              <IconButton onClick={() => onInspect(item)} title="View request and response">
                🔍
              </IconButton>
              <IconButton onClick={() => onReplay(item)} title="Send again">
                ↻
              </IconButton>
            </div>
            <div className="mt-1 text-xs text-[var(--fg)] truncate">
              {item.name?.trim() || <span className="text-[var(--muted-fg)] italic">Unnamed request</span>}
            </div>
            <div className="text-[10px] text-[var(--muted-fg)] truncate font-mono">{item.url}</div>
          </div>
        ))}
      </div>
    </aside>
  );
}

function IconButton({
  onClick,
  title,
  children,
}: {
  onClick: () => void;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      title={title}
      aria-label={title}
      className="w-6 h-6 shrink-0 flex items-center justify-center rounded text-xs text-[var(--muted-fg)] hover:text-[var(--fg)] hover:bg-[var(--bg-elev-2)]"
    >
      {children}
    </button>
  );
}
